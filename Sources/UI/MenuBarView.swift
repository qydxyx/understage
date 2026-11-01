import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject private var settings = VendorSettings.shared
    @ObservedObject private var history = TaskHistory.shared
    @ObservedObject private var jobs = JobQueue.shared
    @ObservedObject private var undo = UndoJournal.shared
    @ObservedObject private var rules = RuleStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Understage")
                .font(.headline)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Button("Grant Accessibility") {
                PermissionGate.promptAccessibility()
            }
            Button("Grant Finder Access") {
                PermissionGate.promptFinderAutomation()
            }
            Button("Settings…") {
                SettingsPresenter.shared.open()
            }
            .keyboardShortcut(",", modifiers: .command)
            if !settings.hotKeyRegistered, settings.hotKey != .disabled {
                Text("Shortcut is already used by another app.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if jobs.runningCount > 0 {
                Text(L10n.format("%ld running", jobs.runningCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let last = undo.last {
                Button(L10n.format("Undo %@", last.summary)) {
                    _ = undo.undoLast()
                }
            }
            if !rules.favorites.isEmpty {
                Menu("Favorites") {
                    ForEach(rules.favorites.prefix(12)) { favorite in
                        Button(favorite.query) {
                            DockingController.shared.prefillFrontBar(favorite.query, submit: true)
                        }
                    }
                }
            }
            if !history.entries.isEmpty {
                Divider()
                Menu("History") {
                    ForEach(history.entries.prefix(12)) { entry in
                        Button("\(entry.ok ? "✓" : "✕") \(entry.query)") {
                            DockingController.shared.prefillFrontBar(entry.query, submit: false)
                        }
                    }
                }
            }
            Divider()
            Button("Quit Understage") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        let p = appModel.permissions
        if p.allGranted {
            return L10n.tr("Watching Finder windows")
        }
        if !p.accessibility {
            return L10n.tr("Needs Accessibility")
        }
        return L10n.tr("Needs Finder automation")
    }
}
