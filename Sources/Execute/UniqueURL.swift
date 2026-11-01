import Foundation

enum UniqueURL {
    static func next(
        in directory: URL,
        name: String,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let ns = name as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension
        var index = 0
        while true {
            let candidateName: String
            if index == 0 {
                candidateName = name
            } else if ext.isEmpty {
                candidateName = "\(base)_\(index)"
            } else {
                candidateName = "\(base)_\(index).\(ext)"
            }
            let url = directory.appendingPathComponent(candidateName)
            if !exists(url) { return url }
            index += 1
        }
    }
}

enum FileMoves {
    /// Case-only renames on a case-insensitive volume fail with "file exists".
    /// Move through a temporary name in the same directory.
    static func move(_ from: URL, to: URL) throws {
        let fm = FileManager.default
        let sameParent = from.deletingLastPathComponent().standardizedFileURL.path
            == to.deletingLastPathComponent().standardizedFileURL.path
        let caseOnly = sameParent
            && from.lastPathComponent != to.lastPathComponent
            && from.lastPathComponent.compare(to.lastPathComponent, options: .caseInsensitive) == .orderedSame
        if caseOnly && fm.fileExists(atPath: to.path) {
            let temp = UniqueURL.next(
                in: from.deletingLastPathComponent(),
                name: ".understage-tmp-\(UUID().uuidString)"
            )
            try fm.moveItem(at: from, to: temp)
            do {
                try fm.moveItem(at: temp, to: to)
            } catch {
                try? fm.moveItem(at: temp, to: from)
                throw error
            }
            return
        }
        try fm.moveItem(at: from, to: to)
    }
}
