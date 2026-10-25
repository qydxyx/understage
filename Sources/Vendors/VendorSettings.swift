import Foundation

@MainActor
final class VendorSettings: ObservableObject {
    static let shared = VendorSettings()

    @Published var vendor: VendorID {
        didSet { UserDefaults.standard.set(vendor.rawValue, forKey: Keys.vendor) }
    }

    @Published var model: String {
        didSet { saveModel() }
    }

    @Published var customBaseURL: String {
        didSet { UserDefaults.standard.set(customBaseURL, forKey: Keys.customBase) }
    }

    @Published var autoRun: AutoRunSettings {
        didSet {
            if let data = try? JSONEncoder().encode(autoRun) {
                UserDefaults.standard.set(data, forKey: Keys.autoRun)
            }
        }
    }

    @Published var allowAgent: Bool {
        didSet { UserDefaults.standard.set(allowAgent, forKey: Keys.allowAgent) }
    }

    @Published var hotKey: HotKeyOption {
        didSet {
            UserDefaults.standard.set(hotKey.rawValue, forKey: Keys.hotKey)
            applyHotKey()
        }
    }

    @Published var ollamaReachable = false
    @Published var lmStudioReachable = false

    private enum Keys {
        static let vendor = "understage.vendor"
        static let models = "understage.models"
        static let customBase = "understage.customBaseURL"
        static let autoRun = "understage.autoRun"
        static let allowAgent = "understage.allowAgent"
        static let hotKey = "understage.hotKey"
    }

    private var modelsByVendor: [String: String]

    init() {
        let raw = UserDefaults.standard.string(forKey: Keys.vendor) ?? VendorID.openai.rawValue
        let vendorID = VendorID(rawValue: raw) ?? .openai
        let storedModels = UserDefaults.standard.dictionary(forKey: Keys.models) as? [String: String] ?? [:]
        let auto: AutoRunSettings
        if let data = UserDefaults.standard.data(forKey: Keys.autoRun),
           let decoded = try? JSONDecoder().decode(AutoRunSettings.self, from: data)
        {
            auto = decoded
        } else {
            auto = AutoRunSettings()
        }
        vendor = vendorID
        modelsByVendor = storedModels
        model = storedModels[vendorID.rawValue] ?? vendorID.defaultModel
        customBaseURL = UserDefaults.standard.string(forKey: Keys.customBase) ?? VendorID.custom.defaultBaseURL
        autoRun = auto
        if UserDefaults.standard.object(forKey: Keys.allowAgent) == nil {
            allowAgent = true
        } else {
            allowAgent = UserDefaults.standard.bool(forKey: Keys.allowAgent)
        }
        let storedHotKey = UserDefaults.standard.string(forKey: Keys.hotKey)
        hotKey = storedHotKey.flatMap(HotKeyOption.init(rawValue:)) ?? .optionSpace
    }

    func applyHotKey() {
        GlobalHotKeyManager.shared.register(option: hotKey) {
            DockingController.shared.toggleOrFocusFrontmostBar()
        }
    }

    var resolvedBaseURL: String {
        vendor == .custom ? customBaseURL : vendor.defaultBaseURL
    }

    var isConfigured: Bool {
        if !vendor.needsKey { return true }
        return KeychainStore.get(account: vendor.rawValue) != nil
    }

    func apiKey() -> String? {
        KeychainStore.get(account: vendor.rawValue)
    }

    func setAPIKey(_ value: String) {
        KeychainStore.set(value, account: vendor.rawValue)
        objectWillChange.send()
    }

    func selectVendor(_ id: VendorID) {
        vendor = id
        model = modelsByVendor[id.rawValue] ?? id.defaultModel
    }

    func makeProvider() throws -> any ChatProvider {
        guard let url = URL(string: resolvedBaseURL) else { throw ChatProviderError.badURL }
        switch vendor.kind {
        case .anthropic:
            guard let key = apiKey() else { throw ChatProviderError.notConfigured }
            return AnthropicProvider(baseURL: url, apiKey: key)
        case .openaiCompat:
            if vendor.needsKey, apiKey() == nil { throw ChatProviderError.notConfigured }
            return OpenAICompatProvider(baseURL: url, apiKey: apiKey())
        }
    }

    func probeLocal() async {
        ollamaReachable = await ping(URL(string: "http://127.0.0.1:11434/api/tags"))
        lmStudioReachable = await ping(URL(string: "http://127.0.0.1:1234/v1/models"))
    }

    private func saveModel() {
        modelsByVendor[vendor.rawValue] = model
        UserDefaults.standard.set(modelsByVendor, forKey: Keys.models)
    }

    private func ping(_ url: URL?) async -> Bool {
        guard let url else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.4
        request.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200 ..< 500).contains(code)
        } catch {
            return false
        }
    }
}
