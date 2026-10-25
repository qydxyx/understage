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
