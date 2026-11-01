import Foundation

enum BarPhase: Equatable {
    case idle
    case thinking
    case preview(CommandPlan)
    case running(CommandPlan)
    case result(ok: Bool, text: String)
}

@MainActor
final class StageBarModel: ObservableObject {
    @Published var context: StageContext?
    @Published var permissions: PermissionState
    @Published var query: String = ""
    @Published var phase: BarPhase = .idle
    @Published var thinkingNote: String = ""
    @Published var showIdeas = false
    @Published var pendingChoices: [String] = []
    @Published var awaitingReply = false
    @Published var focusToken = UUID()
    private var lastSubmittedQuery = ""
    private var historyIndex: Int?
    private var stashedQuery = ""

    private var session: CommandRunner.Session?
    private var work: Task<Void, Never>?
    private var agentMessages: [ChatMessage] = []
    private var agentFolder: URL?
    private var agentUpdated = Date.distantPast
    private var agentQuery = ""
    private var awaitingAsk = false
    private var agentMutated = false
    private var continueAfterRun = false
    private var lastResultText = ""

    var barHeight: CGFloat {
        var height = BarPlacement.height
        if case .idle = phase, showIdeas { height += 28 }
        if case .idle = phase {} else { height += 22 }
        if !pendingChoices.isEmpty { height += 28 }
        return height
    }

    init(permissions: PermissionState = PermissionGate.current()) {
        self.permissions = permissions
    }

    func submit() {
        switch phase {
        case .preview(let plan):
            guard plan.error == nil, plan.missingTool == nil else {
                phase = .idle
                return
            }
            Task { await run(plan, continueAgent: continueAfterRun) }
        case .thinking, .running:
            return
        case .result, .idle:
            parseQuery()
        }
        DockingController.shared.refresh()
    }

    func requestFieldFocus() {
        focusToken = UUID()
    }

    func navigateHistoryUp() {
        let entries = TaskHistory.shared.entries
        guard !entries.isEmpty else { return }
        if historyIndex == nil {
            stashedQuery = query
            historyIndex = 0
            query = entries[0].query
        } else if let current = historyIndex, current + 1 < entries.count {
            historyIndex = current + 1
            query = entries[current + 1].query
        }
    }

    func navigateHistoryDown() {
        guard let current = historyIndex else { return }
        let entries = TaskHistory.shared.entries
        if current > 0 {
            historyIndex = current - 1
            query = entries[current - 1].query
        } else {
            historyIndex = nil
            query = stashedQuery
        }
    }

    func handleEscape() {
        if phase != .idle {
            cancel()
            return
        }
        if !query.isEmpty {
            query = ""
            historyIndex = nil
            return
        }
        FinderAX.activateFinder()
    }

    func cancel() {
        work?.cancel()
        session?.cancel()
        continueAfterRun = false
        awaitingAsk = false
        awaitingReply = false
        pendingChoices = []
        historyIndex = nil
        phase = .idle
        DockingController.shared.refresh()
    }

    func confirmPreview() {
        if case .preview(let plan) = phase {
            Task { await run(plan, continueAgent: continueAfterRun) }
        }
    }

    func undoLast() {
        let text = UndoJournal.shared.undoLast()
        phase = .result(ok: true, text: text)
        DockingController.shared.refresh()
    }

    func toggleIdeas() {
        showIdeas.toggle()
        if showIdeas { phase = .idle }
        DockingController.shared.refresh()
    }

    func applyIdea(_ idea: Idea) {
        query = idea.query
        showIdeas = false
        parseQuery()
        DockingController.shared.refresh()
    }

    func choose(_ option: String) {
        query = option
        submit()
    }

    func favoriteLast() {
        RuleStore.shared.addFavorite(lastSubmittedQuery)
    }

    private func parseQuery() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSLog("[Understage] Query submitted: '%@'", trimmed)
        historyIndex = nil
        query = ""
        lastSubmittedQuery = trimmed
        showIdeas = false
        pendingChoices = []
        if awaitingAsk {
            awaitingAsk = false
            awaitingReply = false
            Task { await stepAgent(user: trimmed) }
            return
        }
        if let action = InstantParser.parse(trimmed) {
            present(instant: action, query: trimmed)
            return
        }
        if VendorSettings.shared.allowAgent {
            startAgent(trimmed)
        } else {
            askModel(trimmed)
        }
    }

    private func present(instant action: InstantAction, query: String) {
        var plan = CommandPlanner.plan(
            action: action,
            query: query,
            selected: context?.selected ?? [],
            folder: context?.folderURL,
            tools: .system
        )
        if let error = plan.error {
            phase = .result(ok: false, text: error)
            TaskHistory.shared.record(query: query, summary: error, ok: false)
            return
        }
        let selectedURLs = (context?.selected ?? []).map(\.url)
        let prediction = Predictor.analyze(
            plan: plan,
            folder: context?.folderURL,
            selected: selectedURLs
        )
        if prediction.risk == .forbidden {
            let text = prediction.reasons.joined(separator: "; ")
            phase = .result(ok: false, text: text)
            TaskHistory.shared.record(query: query, summary: text, ok: false)
            return
        }
        plan.autoRun = AutoRunPolicy.allows(prediction, settings: VendorSettings.shared.autoRun)
        continueAfterRun = false
        if plan.autoRun {
            Task { await run(plan, continueAgent: false) }
        } else {
            phase = .preview(plan)
        }
    }

    private func askModel(_ query: String) {
        let settings = VendorSettings.shared
        guard settings.isConfigured else {
            phase = .result(ok: false, text: String(localized: "Add an API key or start a local model in Settings."))
            return
        }
        let context = self.context
        let chinese = Locale.current.language.languageCode?.identifier == "zh"
        phase = .thinking
        thinkingNote = ""
        work = Task {
            do {
                let provider = try settings.makeProvider()
                let messages = [
                    ChatMessage(
                        role: .system,
                        content: CommandGenerator.systemPrompt(
                            chinese: chinese,
                            rules: RuleStore.shared.promptBlock(query: query, folder: context?.folderURL)
                        )
                    ),
                    ChatMessage(
                        role: .user,
                        content: CommandGenerator.userPrompt(
                            query: query,
                            folder: context?.folderURL,
                            selected: context?.selected ?? []
                        )
                    ),
                ]
                let reply = try await provider.complete(messages: messages, model: settings.model)
                if Task.isCancelled { return }
                let generated = try CommandGenerator.parseReply(reply)
                let plan = CommandGenerator.plan(
                    from: generated,
                    query: query,
                    folder: context?.folderURL,
                    selected: (context?.selected ?? []).map(\.url),
                    autoRun: settings.autoRun
                )
                continueAfterRun = false
                if let error = plan.error {
                    phase = .result(ok: false, text: error)
                    TaskHistory.shared.record(query: query, summary: error, ok: false)
                } else if plan.autoRun {
                    await run(plan, continueAgent: false)
                } else {
                    phase = .preview(plan)
                }
            } catch {
                if Task.isCancelled { return }
                phase = .result(ok: false, text: error.localizedDescription)
                TaskHistory.shared.record(query: query, summary: error.localizedDescription, ok: false)
            }
            DockingController.shared.refresh()
        }
    }

    private func startAgent(_ query: String) {
        let settings = VendorSettings.shared
        guard settings.isConfigured else {
            phase = .result(ok: false, text: String(localized: "Add an API key or start a local model in Settings."))
            return
        }
        let folder = context?.folderURL
        if folder != agentFolder || Date().timeIntervalSince(agentUpdated) > 600 {
            agentMessages = []
            agentFolder = folder
        }
        agentQuery = query
        agentMutated = false
        pendingChoices = []
        awaitingReply = false
        let exts = (context?.selected ?? []).map(\.url.pathExtension).filter { !$0.isEmpty }
        let skills = SkillCatalog.promptBlock(extensions: exts.isEmpty ? ["*"] : exts)
        let chinese = Locale.current.language.languageCode?.identifier == "zh"
        if agentMessages.isEmpty {
            agentMessages.append(
                ChatMessage(
                    role: .system,
                    content: AgentParser.systemPrompt(
                        skills: skills,
                        chinese: chinese,
                        rules: RuleStore.shared.promptBlock(query: query, folder: folder)
                    )
                )
            )
        }
        let selectedItems = context?.selected ?? []
        let listing = selectedItems.isEmpty ? folder.flatMap { try? AgentTools.list(path: $0) } : nil
        agentMessages.append(
            ChatMessage(
                role: .user,
                content: CommandGenerator.userPrompt(
                    query: query,
                    folder: folder,
                    selected: selectedItems,
                    listing: listing
                )
            )
        )
        work = Task { await stepAgent(user: nil) }
    }

    private func stepAgent(user: String?) async {
        if let user {
            agentMessages.append(ChatMessage(role: .user, content: user))
        }
        let settings = VendorSettings.shared
        phase = .thinking
        thinkingNote = String(localized: "Agent working…")
        DockingController.shared.refresh()
        do {
            let provider = try settings.makeProvider()
            var turns = 0
            var rejectedDone = 0
            while turns < 8 {
                if Task.isCancelled { return }
                turns += 1
                let reply = try await provider.complete(messages: agentMessages, model: settings.model)
                if Task.isCancelled { return }
                agentMessages.append(ChatMessage(role: .assistant, content: reply))
                let call: AgentCall
                do {
                    call = try AgentParser.parse(reply)
                } catch {
                    if turns == 1, let generated = try? CommandGenerator.parseReply(reply) {
                        let plan = CommandGenerator.plan(
                            from: generated,
                            query: agentQuery,
                            folder: context?.folderURL,
                            selected: (context?.selected ?? []).map(\.url),
                            autoRun: settings.autoRun
                        )
                        continueAfterRun = false
                        if let error = plan.error {
                            phase = .result(ok: false, text: error)
                            TaskHistory.shared.record(query: agentQuery, summary: error, ok: false)
                        } else if plan.autoRun {
                            await run(plan, continueAgent: false)
                        } else {
                            phase = .preview(plan)
                        }
                        DockingController.shared.refresh()
                        return
                    }
                    throw error
                }
                thinkingNote = call.summary
                agentUpdated = Date()
                switch call.tool {
                case .done:
                    let finished = AgentFinish.result(
                        query: agentQuery,
                        summary: call.summary,
                        mutated: agentMutated,
                        filesLeft: looseFilesLeft()
                    )
                    if !finished.ok, rejectedDone < 2 {
                        rejectedDone += 1
                        var note = "ERROR: \(finished.text) Do not call done. Next JSON must be one move call whose moves array contains every remaining file."
                        if let folder = context?.folderURL, let listing = try? AgentTools.list(path: folder) {
                            note += "\nFolder contents:\n\(listing)"
                        }
                        agentMessages.append(ChatMessage(role: .user, content: note))
                        continue
                    }
                    pendingChoices = []
                    awaitingReply = false
                    phase = .result(ok: finished.ok, text: finished.text)
                    TaskHistory.shared.record(query: agentQuery, summary: finished.text, ok: finished.ok)
                    DockingController.shared.refresh()
                    return
                case .askUser:
                    awaitingAsk = true
                    awaitingReply = true
                    pendingChoices = call.options
                    phase = .result(ok: true, text: call.question ?? call.summary)
                    DockingController.shared.refresh()
                    return
                case .list, .inspect, .readText:
                    let observation = try observe(call)
                    agentMessages.append(ChatMessage(role: .user, content: "TOOL_RESULT:\n\(observation)"))
                    continue
                case .run, .trash, .move, .reveal:
                    let plan = try AgentTools.plan(
                        from: call,
                        query: agentQuery,
                        folder: context?.folderURL,
                        selected: (context?.selected ?? []).map(\.url),
                        autoRun: settings.autoRun
                    )
                    if let error = plan.error {
                        agentMessages.append(ChatMessage(role: .user, content: "TOOL_RESULT:\nERROR \(error)"))
                        continue
                    }
                    if plan.autoRun {
                        var text = await execute(plan)
                        if call.tool == .move, plan.steps.count < 2, looseFilesLeft() > 0 {
                            let left = looseFilesLeft()
                            text += "\nMORE_FILES: \(left) files remain. Reply with ONE move whose moves array includes every remaining file. Do not move one file per turn."
                        }
                        agentMessages.append(ChatMessage(role: .user, content: "TOOL_RESULT:\n\(text)"))
                        continue
                    }
                    continueAfterRun = true
                    phase = .preview(plan)
                    DockingController.shared.refresh()
                    return
                }
            }
            let stopped = String(localized: "Agent stopped after too many steps.")
            phase = .result(ok: false, text: stopped)
            TaskHistory.shared.record(query: agentQuery, summary: stopped, ok: false)
        } catch {
            if Task.isCancelled { return }
            phase = .result(ok: false, text: error.localizedDescription)
            TaskHistory.shared.record(query: agentQuery, summary: error.localizedDescription, ok: false)
        }
        DockingController.shared.refresh()
    }

    private func observe(_ call: AgentCall) throws -> String {
        let folder = context?.folderURL
        let selected = (context?.selected ?? []).map(\.url)
        switch call.tool {
        case .list:
            let url = try AgentTools.resolve(call.path ?? folder?.path, folder: folder, selected: selected)
            return try AgentTools.list(path: url)
        case .inspect:
            let url = try AgentTools.resolve(call.path, folder: folder, selected: selected)
            return AgentTools.inspect(path: url)
        case .readText:
            let url = try AgentTools.resolve(call.path, folder: folder, selected: selected)
            return try AgentTools.readText(path: url)
        default:
            return ""
        }
    }

    private func execute(_ plan: CommandPlan) async -> String {
        let outcome = await run(plan, continueAgent: false, recordContinue: false)
        switch outcome {
        case .success(let text): return text.isEmpty ? plan.summary : text
        case .failure(let text): return "ERROR \(text)"
        case .cancelled: return "CANCELLED"
        }
    }

    @discardableResult
    private func run(
        _ plan: CommandPlan,
        continueAgent: Bool,
        recordContinue: Bool = true
    ) async -> CommandRunner.Outcome {
        guard self.session == nil else { return .failure("Already running") }
        let session = CommandRunner.Session()
        self.session = session
        continueAfterRun = false
        phase = .running(plan)
        NSLog("[Understage] Executing plan: '%@'", plan.summary)
        let jobID = JobQueue.shared.start(query: plan.query, summary: plan.summary)
        DockingController.shared.refresh()
        let report = await CommandRunner.runWithUndo(plan, session: session)
        self.session = nil
        switch report.outcome {
        case .success(let text):
            if planChangesFiles(plan) { agentMutated = true }
            let display = text.isEmpty ? plan.summary : text
            lastResultText = display
            phase = .result(ok: true, text: display)
            NSLog("[Understage] Plan execution succeeded: '%@'", plan.summary)
            TaskHistory.shared.record(query: plan.query, summary: plan.summary, ok: true)
            UndoJournal.shared.record(query: plan.query, summary: plan.summary, actions: report.undos)
            JobQueue.shared.finish(jobID, status: .done, summary: plan.summary)
            if continueAgent, recordContinue {
                agentMessages.append(ChatMessage(role: .user, content: "TOOL_RESULT:\n\(display)"))
                await stepAgent(user: nil)
            }
        case .failure(let text):
            lastResultText = text
            phase = .result(ok: false, text: text)
            NSLog("[Understage] Plan execution failed: '%@' - error: %@", plan.summary, text)
            TaskHistory.shared.record(query: plan.query, summary: text, ok: false)
            UndoJournal.shared.record(query: plan.query, summary: plan.summary, actions: report.undos)
            JobQueue.shared.finish(jobID, status: .failed, summary: text)
            if continueAgent, recordContinue {
                agentMessages.append(ChatMessage(role: .user, content: "TOOL_RESULT:\nERROR \(text)"))
                await stepAgent(user: nil)
            }
        case .cancelled:
            phase = .result(ok: false, text: String(localized: "Cancelled"))
            UndoJournal.shared.record(query: plan.query, summary: plan.summary, actions: report.undos)
            JobQueue.shared.finish(jobID, status: .cancelled)
        }
        self.session = nil
        DockingController.shared.refresh()
        return report.outcome
    }

    private func looseFilesLeft() -> Int {
        guard let folder = context?.folderURL else { return 0 }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { url in
            let dir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return !dir
        }.count
    }

    private func planChangesFiles(_ plan: CommandPlan) -> Bool {
        if !plan.creates.isEmpty || !plan.trashes.isEmpty { return true }
        return plan.steps.contains { step in
            switch step {
            case .select, .copyPasteboard, .openTerminal, .fileInfo:
                return false
            default:
                return true
            }
        }
    }
}
