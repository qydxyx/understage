import Foundation

enum Risk: String, Equatable, Sendable {
    case read
    case create
    case mutate
    case network
    case unknown
    case forbidden
}

struct Prediction: Equatable, Sendable {
    var risk: Risk
    var creates: [URL]
    var trashes: [URL]
    var overwrites: [URL]
    var reasons: [String]

    var canAutoRun: Bool { risk == .read || risk == .create }
}

enum Predictor {
    static func analyze(
        plan: CommandPlan,
        folder: URL?,
        selected: [URL]
    ) -> Prediction {
        if let error = plan.error {
            return Prediction(risk: .forbidden, creates: [], trashes: [], overwrites: [], reasons: [error])
        }
        if plan.steps.isEmpty {
            return Prediction(risk: .read, creates: [], trashes: [], overwrites: [], reasons: [])
        }

        var risk: Risk = .read
        var reasons: [String] = []
        var creates = plan.creates
        var trashes = plan.trashes
        var overwrites: [URL] = []
        let workspace = workspaceRoots(folder: folder, selected: selected)

        for step in plan.steps {
            switch step {
            case .copyPasteboard, .select, .openTerminal:
                continue
            case .trash(let url):
                risk = escalate(risk, .mutate)
                trashes.append(url)
                if let hit = forbiddenPath(url) {
                    return deny("Refuses to touch \(hit)")
                }
            case .copyFile(_, let to):
                risk = escalate(risk, .create)
                creates.append(to)
                if FileManager.default.fileExists(atPath: to.path) {
                    overwrites.append(to)
                    risk = escalate(risk, .mutate)
                }
            case .move(let from, let to):
                risk = escalate(risk, .mutate)
                if let hit = forbiddenPath(from) ?? forbiddenPath(to) {
                    return deny("Refuses to touch \(hit)")
                }
                if FileManager.default.fileExists(atPath: to.path) {
                    overwrites.append(to)
                }
            case .process(let executable, let arguments):
                let joined = ([executable] + arguments).joined(separator: " ")
                if let why = denyReason(joined) {
                    return deny(why)
                }
                let name = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
                if !allowedExecutable(executable) {
                    risk = escalate(risk, .unknown)
                    reasons.append("Unlisted executable \(name)")
                }
                if networkExecutable(name) {
                    risk = escalate(risk, .network)
                    reasons.append("Network tool \(name)")
                }
                if mutatingExecutable(name) || arguments.contains(where: { $0 == "-rf" || $0 == "--delete" }) {
                    risk = escalate(risk, .mutate)
                } else if creatingExecutable(name) {
                    risk = escalate(risk, .create)
                }
                for arg in arguments {
                    guard looksLikePath(arg) else { continue }
                    let url = URL(fileURLWithPath: (arg as NSString).expandingTildeInPath)
                    if let hit = forbiddenPath(url) {
                        return deny("Refuses to touch \(hit)")
                    }
                    if !isInside(url, roots: workspace), !isSystemReadPath(url) {
                        risk = escalate(risk, .unknown)
                        reasons.append("Path outside folder: \(url.path)")
                    }
                    if FileManager.default.fileExists(atPath: url.path), creatingExecutable(name) {
                        let inferred = inferredOutputs(arguments)
                        if inferred.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
                            overwrites.append(url)
                            risk = escalate(risk, .mutate)
                        }
                    }
                }
                creates.append(contentsOf: inferredOutputs(arguments))
            }
        }

        if !overwrites.isEmpty {
            risk = escalate(risk, .mutate)
            reasons.append("Would overwrite existing files")
        }
        return Prediction(
            risk: risk,
            creates: unique(creates),
            trashes: unique(trashes),
            overwrites: unique(overwrites),
            reasons: reasons
        )
    }

    static func denyReason(_ command: String) -> String? {
        let lower = command.lowercased()
        let patterns = [
            "sudo", "doas ", "diskutil", "launchctl", "nvram", "csrutil",
            "rm -rf /", "rm -r /", "rm -fr /",
            ".ssh/", "/etc/sudoers", "chmod -r 777", "chown -r ",
            "curl ", "wget ", "| sh", "| bash", "|zsh",
            "osascript", "keystroke", "mkfs", "dd if=", "/dev/rdisk", "/dev/disk",
        ]
        for pattern in patterns {
            if lower.contains(pattern) {
                if pattern == "curl " || pattern == "wget " { continue }
                if pattern.hasPrefix("curl") || pattern.hasPrefix("wget") { continue }
                return "Blocked pattern: \(pattern.trimmingCharacters(in: .whitespaces))"
            }
        }
        if lower.contains("sudo") { return "Blocked pattern: sudo" }
        if lower.range(of: #"curl[^\n]*\|\s*(ba)?sh"#, options: .regularExpression) != nil
            || lower.range(of: #"wget[^\n]*\|\s*(ba)?sh"#, options: .regularExpression) != nil
        {
            return "Blocked pattern: download|shell"
        }
        return nil
    }

    private static func deny(_ reason: String) -> Prediction {
        Prediction(risk: .forbidden, creates: [], trashes: [], overwrites: [], reasons: [reason])
    }

    private static func escalate(_ current: Risk, _ next: Risk) -> Risk {
        let rank: [Risk: Int] = [
            .read: 0, .create: 1, .mutate: 2, .network: 3, .unknown: 4, .forbidden: 5,
        ]
        return (rank[next] ?? 0) > (rank[current] ?? 0) ? next : current
    }

    private static func allowedExecutable(_ path: String) -> Bool {
        let prefixes = [
            "/usr/bin/", "/bin/", "/usr/sbin/", "/sbin/",
            "/opt/homebrew/bin/", "/usr/local/bin/", "/opt/local/bin/",
        ]
        if prefixes.contains(where: { path.hasPrefix($0) }) { return true }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return ToolDetector.which(name) == path
    }

    private static func networkExecutable(_ name: String) -> Bool {
        ["curl", "wget", "scp", "sftp", "ssh", "rclone", "nc", "ncat", "ftp"].contains(name)
    }

    private static func mutatingExecutable(_ name: String) -> Bool {
        ["rm", "unlink", "mv"].contains(name)
    }

    private static func creatingExecutable(_ name: String) -> Bool {
        ["sips", "ffmpeg", "afconvert", "textutil", "zip", "ditto", "convert", "magick", "qlmanage"].contains(name)
    }

    private static func looksLikePath(_ arg: String) -> Bool {
        arg.hasPrefix("/") || arg.hasPrefix("~")
    }

    private static func forbiddenPath(_ url: URL) -> String? {
        let path = url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let banned = [
            "\(home)/.ssh", "\(home)/.gnupg", "/etc", "/private/etc",
            "/System", "/usr", "/bin", "/sbin", "/var/root",
        ]
        for root in banned {
            if path == root || path.hasPrefix(root + "/") { return root }
        }
        return nil
    }

    private static func isSystemReadPath(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return ["/usr/", "/bin/", "/sbin/", "/System/", "/Library/", "/opt/", "/private/tmp", "/tmp/"]
            .contains { path.hasPrefix($0) || path == String($0.dropLast()) }
    }

    private static func isInside(_ url: URL, roots: [URL]) -> Bool {
        let path = url.standardizedFileURL.path
        return roots.contains { root in
            let r = root.standardizedFileURL.path
            return path == r || path.hasPrefix(r + "/")
        }
    }

    private static func workspaceRoots(folder: URL?, selected: [URL]) -> [URL] {
        var roots: [URL] = []
        if let folder { roots.append(folder) }
        roots.append(contentsOf: selected.map { $0.deletingLastPathComponent() })
        return roots
    }

    static func inferredOutputs(_ arguments: [String]) -> [URL] {
        var urls: [URL] = []
        let flags: Set<String> = ["--out", "-o", "--output"]
        for index in arguments.indices {
            if flags.contains(arguments[index]), index + 1 < arguments.count {
                urls.append(URL(fileURLWithPath: arguments[index + 1]))
            }
        }
        return urls
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}

struct AutoRunSettings: Equatable, Codable, Sendable {
    var readOnly: Bool = true
    var create: Bool = false
}

enum AutoRunPolicy {
    static func allows(_ prediction: Prediction, settings: AutoRunSettings) -> Bool {
        switch prediction.risk {
        case .read: return settings.readOnly
        case .create: return settings.create && prediction.overwrites.isEmpty
        case .mutate, .network, .unknown, .forbidden: return false
        }
    }
}
