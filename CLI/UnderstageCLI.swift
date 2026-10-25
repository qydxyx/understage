import Foundation

@main
enum UnderstageCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("-h") || args.contains("--help") || args.isEmpty {
            print(usage)
            return
        }
        let yes = args.contains("--yes") || args.contains("-y")
        let query = args.filter { $0 != "--yes" && $0 != "-y" }.joined(separator: " ")
        guard !query.isEmpty else {
            fputs("Missing query\n", stderr)
            exit(2)
        }

        var (folder, selected) = FinderScripting.frontContext()
        if folder == nil {
            folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }
        if selected.isEmpty, let folder {
            selected = cwdItems(in: folder)
        }

        guard let action = InstantParser.parse(query) else {
            fputs("Not an Instant Action. Use the Understage bar for agent/LLM requests.\n", stderr)
            exit(3)
        }

        var plan = CommandPlanner.plan(
            action: action,
            query: query,
            selected: selected,
            folder: folder,
            tools: .system
        )
        let prediction = Predictor.analyze(
            plan: plan,
            folder: folder,
            selected: selected.map(\.url)
        )
        if prediction.risk == .forbidden {
            fputs((prediction.reasons.joined(separator: "; ") + "\n"), stderr)
            exit(4)
        }
        if let error = plan.error {
            fputs(error + "\n", stderr)
            exit(4)
        }

        print(plan.summary)
        for created in plan.creates { print("  + \(created.path)") }
        for trashed in plan.trashes { print("  - \(trashed.path)") }

        if !yes {
            print("Pass --yes to run.")
            exit(0)
        }

        plan.autoRun = true
        let outcome = await CommandRunner.run(plan, session: CommandRunner.Session())
        switch outcome {
        case .success(let text):
            print(text.isEmpty ? "OK" : text)
        case .failure(let text):
            fputs(text + "\n", stderr)
            exit(1)
        case .cancelled:
            fputs("Cancelled\n", stderr)
            exit(1)
        }
    }

    private static func cwdItems(in folder: URL) -> [SelectedItem] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        return urls.filter { $0.lastPathComponent != ".DS_Store" }.map { url in
            let dir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return SelectedItem(url: url, name: url.lastPathComponent, isDirectory: dir)
        }
    }

    static let usage = """
    understage — Instant Actions for the current Finder selection (or cwd)

      understage jpg
      understage --yes zip
      understage "select all pdf"

    Without --yes, prints the plan and exits. LLM/agent commands stay in the app.
    """
}
