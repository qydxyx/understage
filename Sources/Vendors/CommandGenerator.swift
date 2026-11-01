import Foundation

struct GeneratedCommand: Equatable, Sendable {
    var summary: String
    var executable: String
    var arguments: [String]
    var creates: [URL]
}

enum CommandGenerator {
    static func parseReply(_ text: String) throws -> GeneratedCommand {
        let json = try extractJSON(from: text)
        if let error = json["error"] as? String, !error.isEmpty {
            throw GeneratorError.model(error)
        }
        if let executable = json["executable"] as? String, !executable.isEmpty {
            let args = json["arguments"] as? [String] ?? []
            let creates = (json["creates"] as? [String] ?? []).map { URL(fileURLWithPath: $0) }
            let summary = (json["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return GeneratedCommand(
                summary: (summary?.isEmpty == false ? summary! : executable),
                executable: executable,
                arguments: args,
                creates: creates
            )
        }
        if let command = json["command"] as? String, !command.isEmpty {
            return GeneratedCommand(
                summary: (json["summary"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? command,
                executable: "/bin/bash",
                arguments: ["-lc", command],
                creates: (json["creates"] as? [String] ?? []).map { URL(fileURLWithPath: $0) }
            )
        }
        throw GeneratorError.unparsed
    }

    static func plan(
        from generated: GeneratedCommand,
        query: String,
        folder: URL?,
        selected: [URL],
        autoRun: AutoRunSettings
    ) -> CommandPlan {
        var plan = CommandPlan(
            query: query,
            summary: generated.summary,
            steps: [.process(executable: ToolDetector.resolve(generated.executable), arguments: generated.arguments)],
            creates: generated.creates,
            trashes: [],
            reveal: generated.creates,
            autoRun: false
        )
        let prediction = Predictor.analyze(plan: plan, folder: folder, selected: selected)
        if prediction.risk == .forbidden {
            plan.error = prediction.reasons.joined(separator: "; ")
            plan.autoRun = false
            return plan
        }
        if plan.creates.isEmpty {
            plan.creates = prediction.creates
            plan.reveal = prediction.creates
        }
        plan.autoRun = AutoRunPolicy.allows(prediction, settings: autoRun)
        if !prediction.reasons.isEmpty {
            plan.summary += " · " + prediction.reasons.prefix(2).joined(separator: "; ")
        }
        return plan
    }

    static func systemPrompt(chinese: Bool, rules: String = "") -> String {
        let language = chinese
            ? "Write summary in Simplified Chinese."
            : "Write summary in English."
        let ruleBlock = rules.isEmpty ? "" : "\n\(rules)\n"
        return """
        You convert a Finder file request into ONE macOS command. \(language)\(ruleBlock)
        Return ONLY JSON with keys:
        executable (absolute path), arguments (array of strings), summary (one line), creates (array of absolute output paths).
        If impossible, return {"error":"reason"}.
        Rules:
        - Use only the provided absolute file paths. Do not touch any other file.
        - Write outputs in the same directory as the source. Do not move the source into a new folder.
        - Prefer /usr/bin/sips, /usr/bin/afconvert, /usr/bin/textutil, /usr/bin/ditto, /usr/bin/zip, /opt/homebrew/bin/ffmpeg, /usr/bin/mdls.
        - Never sudo, never rm -rf, never write ~/.ssh or /etc, never pipe curl to a shell.
        - Do not overwrite; pick a new filename if the destination exists.
        - No interactive flags. No network unless the user asked.
        Examples:
        {"executable":"/usr/bin/sips","arguments":["-s","format","jpeg","/abs/a.png","--out","/abs/a.jpg"],"summary":"Convert a.png to JPEG","creates":["/abs/a.jpg"]}
        """
    }

    static func userPrompt(query: String, folder: URL?, selected: [SelectedItem], listing: String? = nil) -> String {
        var lines = ["Request: \(query)"]
        if let folder {
            lines.append("Folder: \(folder.path)")
        }
        if selected.isEmpty {
            lines.append("Selected: (none)")
            lines.append("Do not modify files this request does not name.")
        } else {
            lines.append("Selected:")
            for item in selected.prefix(30) {
                let kind = item.isDirectory ? "dir" : "file"
                lines.append("- \(kind)\t\(item.url.path)")
            }
            lines.append("Change only these files. Write new files beside them. Do not move or reorganize anything else.")
        }
        if let listing, !listing.isEmpty {
            lines.append("Folder contents:")
            lines.append(listing)
        }
        return lines.joined(separator: "\n")
    }

    static func extractJSON(from text: String) throws -> [String: Any] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            body = String(trimmed[start ... end])
        } else {
            throw GeneratorError.unparsed
        }
        guard let data = body.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw GeneratorError.unparsed
        }
        return json
    }

    enum GeneratorError: Error, LocalizedError {
        case unparsed
        case model(String)

        var errorDescription: String? {
            switch self {
            case .unparsed: L10n.tr("The model did not return a usable command.")
            case .model(let message): message
            }
        }
    }
}
