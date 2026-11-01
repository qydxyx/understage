import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = VendorSettings.shared
    @ObservedObject private var rules = RuleStore.shared
    @StateObject private var form = SettingsForm()

    var body: some View {
        TabView {
            modelTab.tabItem { Text("Model") }
            agentTab.tabItem { Text("Agent") }
            shortcutTab.tabItem { Text("Shortcut") }
            rulesTab.tabItem { Text("Rules") }
            favoritesTab.tabItem { Text("Favorites") }
            autoRunTab.tabItem { Text("Auto-run") }
        }
        .frame(width: 540, height: 400)
        .onAppear {
            form.apiKey = settings.apiKey() ?? ""
            Task { await settings.probeLocal() }
        }
    }

    private var modelTab: some View {
        Form {
            Section {
                Picker("Vendor", selection: $settings.vendor) {
                    ForEach(VendorID.allCases) { id in
                        Text(id.displayName).tag(id)
                    }
                }
                .onChange(of: settings.vendor) { _, new in
                    settings.selectVendor(new)
                    form.apiKey = settings.apiKey() ?? ""
                }
                TextField("Model", text: $settings.model)
                if settings.vendor == .custom {
                    TextField("Base URL", text: $settings.customBaseURL)
                }
                if settings.vendor.needsKey {
                    SecureField("API key", text: $form.apiKey)
                        .onChange(of: form.apiKey) { _, new in
                            settings.setAPIKey(new)
                        }
                } else {
                    Text(localStatus)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var agentTab: some View {
        Form {
            Section {
                Toggle("Allow multi-step agent", isOn: $settings.allowAgent)
                Text("When on, longer requests can list, inspect, and retry instead of one command.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutTab: some View {
        Form {
            Section {
                Picker("Global Hotkey", selection: $settings.hotKey) {
                    ForEach(HotKeyOption.allCases) { opt in
                        Text(opt.displayName).tag(opt)
                    }
                }
                Text("Summons or focuses the Understage command bar under the active Finder window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.hotKey == .controlSpace {
                    Text("Control+Space is the system shortcut for switching input sources.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !settings.hotKeyRegistered, settings.hotKey != .disabled {
                    Text("Shortcut is already used by another app.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var rulesTab: some View {
        Form {
            Section {
                if rules.rules.isEmpty {
                    Text("No rules yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(rules.rules) { rule in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(rule.trigger.isEmpty ? "*" : rule.trigger)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(rule.instruction)
                        }
                        Spacer()
                        Button("Delete") { rules.removeRule(rule) }
                            .controlSize(.small)
                    }
                }
            }
            Section {
                TextField("Trigger (optional)", text: $form.newTrigger)
                TextField("Instruction", text: $form.newInstruction)
                Button("Add rule") {
                    rules.addRule(trigger: form.newTrigger, instruction: form.newInstruction)
                    form.newTrigger = ""
                    form.newInstruction = ""
                }
                .disabled(form.newInstruction.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .formStyle(.grouped)
    }

    private var favoritesTab: some View {
        Form {
            Section {
                if rules.favorites.isEmpty {
                    Text("Star a successful result in the bar to save it.")
                        .foregroundStyle(.secondary)
                }
                ForEach(rules.favorites) { favorite in
                    HStack {
                        Text(favorite.query)
                        Spacer()
                        Button("Delete") { rules.removeFavorite(favorite) }
                            .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var autoRunTab: some View {
        Form {
            Section {
                Toggle("Read-only commands", isOn: $settings.autoRun.readOnly)
                Toggle("File changes that can be undone", isOn: $settings.autoRun.fileChanges)
                Text("Deletes, overwrites, network, and shell commands still ask first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var localStatus: String {
        switch settings.vendor {
        case .ollama:
            settings.ollamaReachable ? L10n.tr("Ollama is reachable on :11434") : L10n.tr("Ollama not detected on :11434")
        case .lmstudio:
            settings.lmStudioReachable ? L10n.tr("LM Studio is reachable on :1234") : L10n.tr("LM Studio not detected on :1234")
        default:
            ""
        }
    }
}

/// Plain ObservableObject: the SwiftUI `@State` macros need Xcode's macro plugin,
/// this file must also compile with the bare command line tools.
final class SettingsForm: ObservableObject {
    @Published var apiKey = ""
    @Published var newTrigger = ""
    @Published var newInstruction = ""
}
