import Foundation

struct Rule: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var trigger: String
    var instruction: String
    var folderPrefix: String

    init(id: UUID = UUID(), trigger: String, instruction: String, folderPrefix: String = "") {
        self.id = id
        self.trigger = trigger
        self.instruction = instruction
        self.folderPrefix = folderPrefix
    }

    func matches(query: String, folder: URL?) -> Bool {
        if !folderPrefix.isEmpty {
            let path = folder?.path ?? ""
            if !path.hasPrefix(folderPrefix) { return false }
        }
        let needle = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty || needle == "*" { return true }
        return query.localizedCaseInsensitiveContains(needle)
    }
}

struct Favorite: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var query: String

    init(id: UUID = UUID(), query: String) {
        self.id = id
        self.query = query
    }
}

@MainActor
final class RuleStore: ObservableObject {
    static let shared = RuleStore()
    private let rulesKey = "understage.rules"
    private let favoritesKey = "understage.favorites"

    @Published var rules: [Rule] = []
    @Published var favorites: [Favorite] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: rulesKey),
           let decoded = try? JSONDecoder().decode([Rule].self, from: data)
        {
            rules = decoded
        }
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let decoded = try? JSONDecoder().decode([Favorite].self, from: data)
        {
            favorites = decoded
        }
    }

    func addRule(trigger: String, instruction: String, folderPrefix: String = "") {
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }
        rules.append(Rule(trigger: trigger, instruction: instruction, folderPrefix: folderPrefix))
        persistRules()
    }

    func removeRule(_ rule: Rule) {
        rules.removeAll { $0.id == rule.id }
        persistRules()
    }

    func addFavorite(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        if favorites.contains(where: { $0.query == query }) { return }
        favorites.insert(Favorite(query: query), at: 0)
        if favorites.count > 30 { favorites = Array(favorites.prefix(30)) }
        persistFavorites()
    }

    func removeFavorite(_ favorite: Favorite) {
        favorites.removeAll { $0.id == favorite.id }
        persistFavorites()
    }

    func promptBlock(query: String, folder: URL?) -> String {
        Self.promptBlock(rules: rules, query: query, folder: folder)
    }

    nonisolated static func promptBlock(rules: [Rule], query: String, folder: URL?) -> String {
        let matched = rules.filter { $0.matches(query: query, folder: folder) }
        guard !matched.isEmpty else { return "" }
        return "User rules:\n" + matched.map { "- \($0.instruction)" }.joined(separator: "\n")
    }

    private func persistRules() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: rulesKey)
        }
    }

    private func persistFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }
}
