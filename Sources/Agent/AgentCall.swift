import Foundation

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
            question: json["question"] as? String
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
        {"tool":"move","from":"/abs/a","to":"/abs/b","summary":"..."}
        {"tool":"trash","path":"/abs/file"}
        {"tool":"reveal","paths":["/abs/file"]}
        {"tool":"ask_user","question":"..."}
        {"tool":"done","summary":"..."}
        Rules:
        - Stay inside the Finder folder and selected paths.
        - Inspect or list before bulk organize.
        - Never sudo, never rm -rf, never overwrite; unique names.
        - Prefer sips/ffmpeg/ditto/zip/textutil.
        \(extras)
        """
    }
}
