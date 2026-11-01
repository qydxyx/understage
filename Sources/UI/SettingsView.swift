import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = VendorSettings.shared
    @ObservedObject private var rules = RuleStore.shared
    @State private var apiKey: String = ""
    @State private var newTrigger = ""
    @State private var newInstruction = ""

    var body: some View {
        Form {
            Section("Model") {
                Picker("Vendor", selection: $settings.vendor) {
                    ForEach(VendorID.allCases) { id in
                        Text(id.displayName).tag(id)
                    }
                }
                .onChange(of: settings.vendor) { _, new in
                    settings.selectVendor(new)
                    apiKey = settings.apiKey() ?? ""
                }
                TextField("Model", text: $settings.model)
                if settings.vendor == .custom {
                    TextField("Base URL", text: $settings.customBaseURL)
                }
                if settings.vendor.needsKey {
                    SecureField("API key", text: $apiKey)
                        .onChange(of: apiKey) { _, new in
                            settings.setAPIKey(new)
                        }
                } else {
                    Text(localStatus)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Agent") {
                Toggle("Allow multi-step agent", isOn: $settings.allowAgent)
                Text("When on, longer requests can list, inspect, and retry instead of one command.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Shortcut") {
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
            Section("Rules") {
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
                TextField("Trigger (optional)", text: $newTrigger)
                TextField("Instruction", text: $newInstruction)
                Button("Add rule") {
                    rules.addRule(trigger: newTrigger, instruction: newInstruction)
                    newTrigger = ""
                    newInstruction = ""
                }
                .disabled(newInstruction.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Section("Favorites") {
                ForEach(rules.favorites) { favorite in
                    HStack {
                        Text(favorite.query)
                        Spacer()
                        Button("Delete") { rules.removeFavorite(favorite) }
                            .controlSize(.small)
                    }
                }
                if rules.favorites.isEmpty {
                    Text("Star a successful result in the bar to save it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Auto-run") {
                Toggle("Read-only commands", isOn: $settings.autoRun.readOnly)
                Toggle("File changes that can be undone", isOn: $settings.autoRun.fileChanges)
                Text("Deletes, overwrites, network, and shell commands still ask first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 520)
        .onAppear {
            apiKey = settings.apiKey() ?? ""
            Task { await settings.probeLocal() }
        }
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
