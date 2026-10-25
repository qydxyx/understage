import Foundation

struct Skill: Equatable, Sendable {
    var id: String
    var title: String
    var match: [String]
    var body: String

    func matches(extensions: [String]) -> Bool {
        if match.contains("*") { return true }
        let ext = Set(extensions.map { $0.lowercased() })
        return match.contains { ext.contains($0.lowercased()) }
    }
}

enum SkillCatalog {
    static func load() -> [Skill] {
        bundled() + user()
    }

    static func relevant(extensions: [String]) -> [Skill] {
        load().filter { $0.matches(extensions: extensions) }
    }

    static func promptBlock(extensions: [String]) -> String {
        let skills = relevant(extensions: extensions)
        guard !skills.isEmpty else { return "" }
        return skills.map { skill in
            "### \(skill.title) (\(skill.id))\n\(skill.body)"
        }.joined(separator: "\n\n")
    }

    static func parse(_ markdown: String, fallbackID: String) -> Skill {
        var id = fallbackID
        var title = fallbackID
        var match: [String] = ["*"]
        var body = markdown
        if markdown.hasPrefix("---"), let end = markdown.range(of: "\n---") {
            let header = String(markdown[markdown.index(markdown.startIndex, offsetBy: 3) ..< end.lowerBound])
            body = String(markdown[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            for line in header.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                switch parts[0] {
                case "id": id = parts[1]
                case "title": title = parts[1]
                case "match":
                    match = parts[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                default: break
                }
            }
        }
        return Skill(id: id, title: title, match: match, body: body)
    }

    private static func bundled() -> [Skill] {
        let urls =
            Bundle.main.urls(forResourcesWithExtension: "md", subdirectory: "Skills")
            ?? Bundle.main.urls(forResourcesWithExtension: "md", subdirectory: nil)
            ?? []
        return urls.compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return parse(text, fallbackID: url.deletingPathExtension().lastPathComponent)
        }
    }

    private static func user() -> [Skill] {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Understage/Skills")
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return urls.filter { $0.pathExtension == "md" }.compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return parse(text, fallbackID: url.deletingPathExtension().lastPathComponent)
        }
    }
}
