import Foundation

enum AgentTools {
    enum ToolError: Error, LocalizedError {
        case missingPath
        case outsideWorkspace
        case notFound(String)

        var errorDescription: String? {
            switch self {
            case .missingPath: "Missing path"
            case .outsideWorkspace: "Path is outside the Finder folder"
            case .notFound(let path): "Not found: \(path)"
            }
        }
    }

    static func inWorkspace(_ url: URL, folder: URL?, selected: [URL]) -> Bool {
        let roots: [URL] = [folder].compactMap { $0 } + selected.map { $0.deletingLastPathComponent() } + selected
        let path = url.standardizedFileURL.path
        return roots.contains { root in
            let r = root.standardizedFileURL.path
            return path == r || path.hasPrefix(r + "/")
        }
    }

    static func resolve(_ raw: String?, folder: URL?, selected: [URL]) throws -> URL {
        guard let raw, !raw.isEmpty else { throw ToolError.missingPath }
        let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        guard inWorkspace(url, folder: folder, selected: selected) else { throw ToolError.outsideWorkspace }
        return url
    }

    static func list(path: URL) throws -> String {
        let urls = try FileManager.default.contentsOfDirectory(
            at: path,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let lines = urls.prefix(80).map { url -> String in
            let dir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return "\(dir ? "dir" : "file")\t\(url.path)"
        }
        let extra = urls.count > 80 ? "\n… \(urls.count - 80) more" : ""
        return lines.joined(separator: "\n") + extra
    }

    static func inspect(path: URL) -> String {
        let item = SelectedItem(url: path, name: path.lastPathComponent, isDirectory: path.hasDirectoryPath)
        let fields: [InfoField] = [.path, .size, .fileType, .resolution, .duration, .codec]
        return fields.map { FileInfo.report(field: $0, items: [item], folder: path.deletingLastPathComponent()) }
            .joined(separator: "\n")
    }

    static func readText(path: URL, limit: Int = 4000) throws -> String {
        guard FileManager.default.fileExists(atPath: path.path) else { throw ToolError.notFound(path.path) }
        guard let text = try? String(contentsOf: path, encoding: .utf8) else {
            return "Not UTF-8 text"
        }
        if text.count <= limit { return text }
        return String(text.prefix(limit)) + "\n…"
    }

    static func plan(
        from call: AgentCall,
        query: String,
        folder: URL?,
        selected: [URL],
        autoRun: AutoRunSettings
    ) throws -> CommandPlan {
        switch call.tool {
        case .run:
            guard let executable = call.executable, !executable.isEmpty else {
                throw CommandGenerator.GeneratorError.model("run needs executable")
            }
            return CommandGenerator.plan(
                from: GeneratedCommand(
                    summary: call.summary,
                    executable: executable,
                    arguments: call.arguments,
                    creates: call.creates
                ),
                query: query,
                folder: folder,
                selected: selected,
                autoRun: autoRun
            )
        case .trash:
            let url = try resolve(call.path, folder: folder, selected: selected)
            var plan = CommandPlan(
                query: query,
                summary: call.summary.isEmpty ? "Trash \(url.lastPathComponent)" : call.summary,
                steps: [.trash(url)],
                creates: [],
                trashes: [url],
                reveal: [],
                autoRun: false
            )
            let prediction = Predictor.analyze(plan: plan, folder: folder, selected: selected)
            if prediction.risk == .forbidden {
                plan.error = prediction.reasons.joined(separator: "; ")
            }
            plan.autoRun = AutoRunPolicy.allows(prediction, settings: autoRun)
            return plan
        case .move:
            var pairs = call.moves
            if pairs.isEmpty, let from = call.from, let to = call.to {
                pairs = [AgentMove(from: from, to: to)]
            }
            guard !pairs.isEmpty else { throw ToolError.missingPath }
            var steps: [PlanStep] = []
            for pair in pairs {
                let from = try resolve(pair.from, folder: folder, selected: selected)
                let to = try resolve(pair.to, folder: folder, selected: selected)
                steps.append(.move(from: from, to: to))
            }
            let summary = call.summary.isEmpty ? "Move \(steps.count) file(s)" : call.summary
            var plan = CommandPlan(
                query: query,
                summary: summary,
                steps: steps,
                creates: [],
                trashes: [],
                reveal: [],
                autoRun: false
            )
            let prediction = Predictor.analyze(plan: plan, folder: folder, selected: selected)
            if prediction.risk == .forbidden {
                plan.error = prediction.reasons.joined(separator: "; ")
            }
            plan.autoRun = AutoRunPolicy.allows(prediction, settings: autoRun)
            return plan
        case .reveal:
            let urls = try (call.paths.isEmpty ? [call.path].compactMap { $0 } : call.paths).map {
                try resolve($0, folder: folder, selected: selected)
            }
            return CommandPlan(
                query: query,
                summary: "Reveal \(urls.count) item(s)",
                steps: [.select(urls)],
                creates: [],
                trashes: [],
                reveal: urls,
                autoRun: true
            )
        default:
            throw CommandGenerator.GeneratorError.unparsed
        }
    }
}
