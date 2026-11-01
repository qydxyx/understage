import Foundation

enum UndoAction: Equatable, Codable, Sendable {
    case restoreFromTrash(original: String, trash: String)
    case trashCreated(String)
    case moveBack(from: String, to: String)

    func apply() throws {
        let fm = FileManager.default
        switch self {
        case .restoreFromTrash(let original, let trash):
            let dest = URL(fileURLWithPath: original)
            let src = URL(fileURLWithPath: trash)
            if fm.fileExists(atPath: dest.path) {
                let unique = UniqueURL.next(in: dest.deletingLastPathComponent(), name: dest.lastPathComponent)
                try fm.moveItem(at: src, to: unique)
            } else {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: src, to: dest)
            }
        case .trashCreated(let path):
            var resulting: NSURL?
            try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resulting)
        case .moveBack(let from, let to):
            try FileMoves.move(URL(fileURLWithPath: from), to: URL(fileURLWithPath: to))
        }
    }
}

struct UndoBatch: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var date: Date
    var query: String
    var summary: String
    var actions: [UndoAction]

    init(id: UUID = UUID(), date: Date = Date(), query: String, summary: String, actions: [UndoAction]) {
        self.id = id
        self.date = date
        self.query = query
        self.summary = summary
        self.actions = actions
    }
}

@MainActor
final class UndoJournal: ObservableObject {
    static let shared = UndoJournal()
    private let key = "understage.undo"
    private let limit = 20

    @Published private(set) var batches: [UndoBatch] = []

    var last: UndoBatch? { batches.first }

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([UndoBatch].self, from: data)
        {
            batches = decoded
        }
    }

    func record(query: String, summary: String, actions: [UndoAction]) {
        guard !actions.isEmpty else { return }
        batches.insert(UndoBatch(query: query, summary: summary, actions: actions), at: 0)
        if batches.count > limit { batches = Array(batches.prefix(limit)) }
        save()
    }

    func undoLast() -> String {
        guard let batch = batches.first else {
            return String(localized: "Nothing to undo")
        }
        let outcome = Self.apply(batch.actions)
        if outcome.remaining.isEmpty {
            batches.removeFirst()
        } else {
            batches[0].actions = outcome.remaining
        }
        save()
        if outcome.errors.isEmpty {
            return String(localized: "Undid: \(batch.summary)")
        }
        return String(localized: "Undo partially failed: \(outcome.errors.joined(separator: "; "))")
    }

    /// Applies actions from last to first. Actions that throw stay in `remaining`.
    nonisolated static func apply(_ actions: [UndoAction]) -> (errors: [String], remaining: [UndoAction]) {
        var errors: [String] = []
        var failed: [UndoAction] = []
        for action in actions.reversed() {
            do {
                try action.apply()
            } catch {
                errors.append(error.localizedDescription)
                failed.append(action)
            }
        }
        failed.reverse()
        return (errors, failed)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(batches) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
