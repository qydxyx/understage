import Foundation

struct ScriptingFinderWindow: Equatable, Sendable {
    var id: Int
    var name: String
    var width: Double
    var height: Double
    var target: URL?
}

enum FinderScripting {
    static func listWindows() -> [ScriptingFinderWindow] {
        snapshot().windows
    }

    static func snapshot() -> (windows: [ScriptingFinderWindow], frontSelection: [SelectedItem]) {
        let source = """
        function run() {
          const finder = Application("Finder");
          const result = [];
          const windows = finder.finderWindows();
          for (let i = 0; i < windows.length; i++) {
            const w = windows[i];
            let target = "";
            try {
              target = String(w.target().url());
            } catch (e) {}
            const b = w.bounds();
            result.push({
              id: w.id(),
              name: String(w.name()),
              width: b.width,
              height: b.height,
              target: target
            });
          }
          const paths = [];
          try {
            const sel = finder.selection();
            for (let i = 0; i < sel.length; i++) {
              try { paths.push(String(sel[i].url())); } catch (e) {}
            }
          } catch (e) {}
          return JSON.stringify({ windows: result, selection: paths });
        }
        """
        guard let json = runJXA(source),
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return ([], []) }
        let rows = object["windows"] as? [[String: Any]] ?? []
        let windows: [ScriptingFinderWindow] = rows.compactMap { row in
            guard let id = row["id"] as? Int, let name = row["name"] as? String else { return nil }
            let width = (row["width"] as? NSNumber)?.doubleValue ?? 0
            let height = (row["height"] as? NSNumber)?.doubleValue ?? 0
            let target = (row["target"] as? String).flatMap(url(fromFinder:))
            return ScriptingFinderWindow(id: id, name: name, width: width, height: height, target: target)
        }
        let paths = object["selection"] as? [String] ?? []
        return (windows, items(fromPaths: paths))
    }

    private static func items(fromPaths paths: [String]) -> [SelectedItem] {
        paths.compactMap(url(fromFinder:)).map { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return SelectedItem(url: url, name: url.lastPathComponent, isDirectory: isDir.boolValue)
        }
    }

    static func matchTarget(
        title: String,
        cocoaSize: CGSize,
        windows: [ScriptingFinderWindow]
    ) -> URL? {
        let named = windows.filter { $0.name == title }
        let pool = named.isEmpty ? windows : named
        guard !pool.isEmpty else { return nil }
        if pool.count == 1 { return pool[0].target }
        return pool.min { a, b in
            sizeDistance(a, cocoaSize) < sizeDistance(b, cocoaSize)
        }?.target
    }

    private static func sizeDistance(_ window: ScriptingFinderWindow, _ size: CGSize) -> Double {
        let dw = window.width - size.width
        let dh = window.height - size.height
        return dw * dw + dh * dh
    }

    /// Select only items already shown in the front Finder window.
    /// `select` of a file in another folder opens a new window.
    static func select(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let list = urls.map { url in
            let escaped = url.path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "POSIX file \"\(escaped)\""
        }.joined(separator: ", ")
        let source = """
        tell application "Finder"
            if (count of Finder windows) is 0 then return
            set destPath to POSIX path of (target of front Finder window as alias)
            if destPath does not end with "/" then set destPath to destPath & "/"
            set chosen to {}
            repeat with f in {\(list)}
                try
                    set parentPath to POSIX path of (container of f as alias)
                    if parentPath does not end with "/" then set parentPath to parentPath & "/"
                    if parentPath is destPath then set end of chosen to contents of f
                end try
            end repeat
            if (count of chosen) is 0 then return
            select chosen
        end tell
        """
        _ = runAppleScript(source)
    }

    static func frontContext() -> (folder: URL?, selected: [SelectedItem]) {
        let source = """
        function run() {
          const finder = Application("Finder");
          let folder = "";
          try { folder = String(finder.finderWindows[0].target().url()); } catch (e) {}
          const paths = [];
          try {
            const sel = finder.selection();
            for (let i = 0; i < sel.length; i++) {
              try { paths.push(String(sel[i].url())); } catch (e) {}
            }
          } catch (e) {}
          return JSON.stringify({ folder: folder, paths: paths });
        }
        """
        guard let json = runJXA(source),
              let data = json.data(using: .utf8),
              let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return (nil, []) }
        let folder = (row["folder"] as? String).flatMap(url(fromFinder:))
        let selected = items(fromPaths: row["paths"] as? [String] ?? [])
        return (folder, selected)
    }

    private static func url(fromFinder string: String) -> URL? {
        if string.isEmpty { return nil }
        if let url = URL(string: string), url.isFileURL { return url }
        if string.hasPrefix("/") { return URL(fileURLWithPath: string) }
        return URL(string: string)
    }

    private static func runAppleScript(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private static func runJXA(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", source]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
