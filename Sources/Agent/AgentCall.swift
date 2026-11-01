import Foundation

struct AgentMove: Equatable, Sendable {
    var from: String
    var to: String
}

struct AgentCall: Equatable, Sendable {
    enum Tool: String, Equatable, Sendable {
        case list, inspect, readText = "read_text", run, trash, reveal, move, done, askUser = "ask_user"
    }

    var tool: Tool
    var summary: String
    var path: String?
    var paths: [String]
    var executable: String?
    var arguments: [String]
    var creates: [URL]
    var from: String?
    var to: String?
    var question: String?
    var options: [String] = []
    var moves: [AgentMove] = []
}

enum AgentParser {
    static func parse(_ text: String) throws -> AgentCall {
        let json = try CommandGenerator.extractJSON(from: text)
        if let error = json["error"] as? String, !error.isEmpty {
            throw CommandGenerator.GeneratorError.model(error)
        }
        let name = ((json["tool"] as? String) ?? "").lowercased()
        guard let tool = AgentCall.Tool(rawValue: name) else {
            throw CommandGenerator.GeneratorError.unparsed
        }
        let creates = (json["creates"] as? [String] ?? []).map { URL(fileURLWithPath: $0) }
        let paths = json["paths"] as? [String] ?? []
        let moves = (json["moves"] as? [[String: Any]] ?? []).compactMap { row -> AgentMove? in
            guard let from = row["from"] as? String, let to = row["to"] as? String else { return nil }
            let trimmedFrom = from.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedTo = to.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedFrom.isEmpty, !trimmedTo.isEmpty else { return nil }
            return AgentMove(from: trimmedFrom, to: trimmedTo)
        }
        return AgentCall(
            tool: tool,
            summary: (json["summary"] as? String) ?? name,
            path: json["path"] as? String,
            paths: paths,
            executable: json["executable"] as? String,
            arguments: json["arguments"] as? [String] ?? [],
            creates: creates,
            from: json["from"] as? String,
            to: json["to"] as? String,
            question: json["question"] as? String,
            options: (json["options"] as? [String] ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            moves: moves
        )
    }

    static func systemPrompt(skills: String, chinese: Bool, rules: String = "") -> String {
        let language = chinese
            ? "Write summary in Simplified Chinese."
            : "Write summary in English."
        let extras = [rules, skills.isEmpty ? "" : "Skills:\n\(skills)"]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return """
        You are Understage, a Finder file agent. \(language)
        Reply with ONE JSON object per turn, no markdown.
        Tools:
        {"tool":"list","path":"/abs/folder"}
        {"tool":"inspect","path":"/abs/file"}
        {"tool":"read_text","path":"/abs/file"}
        {"tool":"run","executable":"/usr/bin/sips","arguments":["..."],"creates":["/abs/out"],"summary":"..."}
        {"tool":"move","moves":[{"from":"/abs/a","to":"/abs/Folder/a"},{"from":"/abs/b","to":"/abs/Folder/b"}],"summary":"..."}
        {"tool":"trash","path":"/abs/file"}
        {"tool":"reveal","paths":["/abs/file"]}
        {"tool":"ask_user","question":"...","options":["choice A","choice B"]}
        {"tool":"done","summary":"..."}
        Rules:
        - Do only what this request asks. Do not tidy, sort, rename, or move anything else.
        - If files are selected, change only those files.
        - Write new files in the same directory as the source. Do not create a folder unless the request asks for one.
        - A folder listing is reference. It is not a request to reorganize that folder.
        - Stay inside the Finder folder and selected paths.
        - When a choice is required, call ask_user with 2 to 4 short options.
        - Move only when the user asked to move or organize. Then put every requested move in ONE move call.
        - Do not call reveal.
        - Never sudo, never rm -rf, never overwrite; unique names.
        - Prefer sips/ffmpeg/ditto/zip/textutil.
        \(extras)
        """
    }
}

enum AgentFinish {
    static func result(query: String, summary: String, mutated: Bool, filesLeft: Int = 0) -> (ok: Bool, text: String) {
        let body = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let chinese = L10n.prefersChinese(for: query)
        if asksForChange(query), filesLeft > 0 {
            let note = chinese
                ? "还有 \(filesLeft) 个文件留在原处。"
                : L10n.format("%ld files are still in place.", filesLeft)
            return (false, body.isEmpty ? note : "\(note) \(body)")
        }
        if asksForChange(query), !mutated {
            let note = chinese ? "没有改动任何文件。" : L10n.tr("No files were changed.")
            return (false, body.isEmpty ? note : "\(note) \(body)")
        }
        return (true, body.isEmpty ? summary : body)
    }

    static func asksForChange(_ query: String) -> Bool {
        let lower = query.lowercased()
        let words = ["sort", "move", "organiz", "rename", "archive", "整理", "分类", "分门", "归档", "移动", "重命名"]
        return words.contains { lower.contains($0) }
    }
}
