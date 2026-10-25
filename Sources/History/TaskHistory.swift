import Foundation

struct HistoryEntry: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var date: Date
    var query: String
    var summary: String
    var ok: Bool

    init(id: UUID = UUID(), date: Date = Date(), query: String, summary: String, ok: Bool) {
        self.id = id
        self.date = date
        self.query = query
        self.summary = summary
        self.ok = ok
    }
}

@MainActor
final class TaskHistory: ObservableObject {
    static let shared = TaskHistory()
    private let key = "understage.taskHistory"
    private let limit = 50

    @Published private(set) var entries: [HistoryEntry] = []

    init() {
        load()
    }

    func record(query: String, summary: String, ok: Bool) {
        entries.insert(HistoryEntry(query: query, summary: summary, ok: ok), at: 0)
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
