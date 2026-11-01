import SwiftUI

struct StageBarView: View {
    @ObservedObject var model: StageBarModel
    @ObservedObject private var settings = VendorSettings.shared
    @ObservedObject private var undo = UndoJournal.shared
    @ObservedObject private var rules = RuleStore.shared
    @FocusState private var isFieldFocused: Bool
    var onFieldFocused: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if !model.permissions.accessibility {
                    permissionRow
                } else {
                    contextRow
                }
            }
            if model.permissions.accessibility {
                phaseRow
                if !model.pendingChoices.isEmpty {
                    choicesRow
                }
                if model.showIdeas, case .idle = model.phase {
                    ideasRow
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
        .onChange(of: model.focusToken) { _, _ in
            isFieldFocused = true
        }
        .onKeyPress(.upArrow) {
            model.navigateHistoryUp()
            return .handled
        }
        .onKeyPress(.downArrow) {
            model.navigateHistoryDown()
            return .handled
        }
        .onKeyPress(.escape) {
            model.handleEscape()
            return .handled
        }
    }

    @ViewBuilder
    private var permissionRow: some View {
        Image(systemName: "rectangle.bottomhalf.inset.filled")
            .foregroundStyle(.secondary)
        Text("Understage")
            .font(.headline)
        Spacer()
        if !model.permissions.accessibility {
            Button("Grant Accessibility") {
                PermissionGate.promptAccessibility()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        if !model.permissions.finderAutomation {
            Button("Grant Finder Access") {
                PermissionGate.promptFinderAutomation()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        Button {
            SettingsPresenter.shared.open()
        } label: {
            Image(systemName: "gearshape")
        }
        .buttonStyle(.plain)
        .help("Settings")
    }

    @ViewBuilder
    private var contextRow: some View {
        Text(folderLabel)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: 96, alignment: .leading)
        if selectionCount > 0 {
            Text("\(selectionCount)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .help(selectionNames)
        }
        TextField(model.awaitingReply ? L10n.tr("Reply…") : L10n.tr("Command"), text: $model.query)
            .textFieldStyle(.plain)
            .focused($isFieldFocused)
            .disabled({
                switch model.phase {
                case .thinking, .running: true
                default: false
                }
            }())
            .onSubmit(model.submit)
            .onTapGesture {
                isFieldFocused = true
                onFieldFocused()
            }
        if !model.permissions.finderAutomation {
            Button("Finder") {
                PermissionGate.promptFinderAutomation()
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .help("Grant Finder Access")
        }
        Button {
            model.toggleIdeas()
        } label: {
            Image(systemName: model.showIdeas ? "lightbulb.fill" : "lightbulb")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .help("Ideas")
        Button {
            SettingsPresenter.shared.open()
        } label: {
            Image(systemName: "gearshape")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .help("Settings")
    }

    @ViewBuilder
    private var phaseRow: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .thinking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(model.thinkingNote.isEmpty
                    ? L10n.format("Asking %@…", settings.model.isEmpty ? settings.vendor.displayName : settings.model)
                    : model.thinkingNote)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Button("Cancel", action: model.cancel)
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .preview(let plan):
            HStack(spacing: 8) {
                Text(previewText(plan))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Cancel", action: model.cancel)
                    .buttonStyle(.plain)
                    .font(.caption2)
                Button("Run", action: model.confirmPreview)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .disabled(plan.error != nil || plan.missingTool != nil)
            }
        case .running(let plan):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(plan.summary)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Button("Cancel", action: model.cancel)
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .result(let ok, let text):
            HStack(spacing: 8) {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(model.awaitingReply ? Color.primary : (ok ? Color.secondary : Color.red))
                    .lineLimit(1)
                Spacer()
                if undo.last != nil {
                    Button("Undo", action: model.undoLast)
                        .buttonStyle(.plain)
                        .font(.caption2)
                }
                if ok, !model.awaitingReply {
                    Button("★") { model.favoriteLast() }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .help("Save favorite")
                }
            }
        }
    }

    @ViewBuilder
    private var choicesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.pendingChoices, id: \.self) { choice in
                    Button(choice) { model.choose(choice) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var ideasRow: some View {
        let ideas = Ideas.suggestions(
            selected: model.context?.selected ?? [],
            folder: model.context?.folderURL,
            favorites: rules.favorites
        )
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ideas) { idea in
                    Button(idea.title) {
                        model.applyIdea(idea)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
    }

    private func previewText(_ plan: CommandPlan) -> String {
        if let missing = plan.missingTool, missing == "ffmpeg" {
            return plan.summary
        }
        var parts = [plan.summary]
        if !plan.creates.isEmpty {
            parts.append(plan.creates.prefix(3).map(\.lastPathComponent).joined(separator: ", "))
        }
        if !plan.trashes.isEmpty {
            parts.append(L10n.format("Trash: %@", plan.trashes.prefix(3).map(\.lastPathComponent).joined(separator: ", ")))
        }
        return parts.joined(separator: " · ")
    }

    private var folderLabel: String {
        if let name = model.context?.folderName, !name.isEmpty { return name }
        if let title = model.context?.title, !title.isEmpty { return title }
        return L10n.tr("Finder")
    }

    private var selectionCount: Int {
        model.context?.selected.count ?? 0
    }

    private var selectionNames: String {
        (model.context?.selected ?? []).prefix(8).map(\.name).joined(separator: ", ")
    }
}
