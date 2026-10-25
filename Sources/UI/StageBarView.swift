import SwiftUI

struct StageBarView: View {
    @ObservedObject var model: StageBarModel
    @ObservedObject private var settings = VendorSettings.shared
    @ObservedObject private var undo = UndoJournal.shared
    @ObservedObject private var rules = RuleStore.shared
    var onFieldFocused: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if !model.permissions.allGranted {
                    permissionRow
                } else {
                    contextRow
                }
            }
            if model.permissions.allGranted {
                phaseRow
                if model.showIdeas, case .idle = model.phase {
                    ideasRow
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
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
        Image(systemName: model.context?.isDesktop == true ? "desktopcomputer" : "folder")
            .foregroundStyle(.secondary)
        Text(folderLabel)
            .font(.system(.body, design: .rounded))
            .fontWeight(.medium)
            .lineLimit(1)
            .frame(maxWidth: 160, alignment: .leading)
        chips
        TextField("Enter query or command", text: $model.query)
            .textFieldStyle(.plain)
            .disabled({
                if case .thinking = model.phase { true } else { false }
            }())
            .onSubmit(model.submit)
            .onTapGesture(perform: onFieldFocused)
        Button {
            model.toggleIdeas()
        } label: {
            Image(systemName: model.showIdeas ? "lightbulb.fill" : "lightbulb")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Ideas")
        Button {
            SettingsPresenter.shared.open()
        } label: {
            HStack(spacing: 4) {
                Text(settings.vendor.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                    ? "Asking \(settings.model.isEmpty ? settings.vendor.displayName : settings.model)…"
                    : model.thinkingNote)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Button("Cancel", action: model.cancel)
                    .controlSize(.small)
            }
        case .preview(let plan):
            HStack(spacing: 8) {
                Text(previewText(plan))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button("Cancel", action: model.cancel)
                    .controlSize(.small)
                Button("Run", action: model.confirmPreview)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(plan.error != nil || plan.missingTool != nil)
                    .keyboardShortcut(.return)
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
                    .controlSize(.small)
            }
        case .result(let ok, let text):
            HStack(spacing: 8) {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(ok ? Color.secondary : Color.red)
                    .lineLimit(3)
                Spacer()
                if undo.last != nil {
                    Button("Undo", action: model.undoLast)
                        .controlSize(.small)
                }
                if ok {
                    Button("★") { model.favoriteLast() }
                        .controlSize(.small)
                        .help("Save favorite")
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
            parts.append("Trash: " + plan.trashes.prefix(3).map(\.lastPathComponent).joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    private var folderLabel: String {
        if let name = model.context?.folderName, !name.isEmpty { return name }
        if let title = model.context?.title, !title.isEmpty { return title }
        return String(localized: "Finder")
    }

    @ViewBuilder
    private var chips: some View {
        let items = model.context?.selected ?? []
        if items.isEmpty {
            Text("No selection")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 6) {
                ForEach(items.prefix(3)) { item in
                    Text(item.name)
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                if items.count > 3 {
                    Text("+\(items.count - 3)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
