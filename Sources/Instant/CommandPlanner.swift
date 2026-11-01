import Foundation

enum CommandPlanner {
    static func plan(
        action: InstantAction,
        query: String,
        selected: [SelectedItem],
        folder: URL?,
        tools: Toolset,
        exists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> CommandPlan {
        switch action {
        case .convert(let format):
            return convert(format, query: query, selected: selected, tools: tools, exists: exists)
        case .scaleVideo(let height):
            return scaleVideo(height, query: query, selected: selected, tools: tools, exists: exists)
        case .extractAudio:
            return extractAudio(query: query, selected: selected, tools: tools, exists: exists)
        case .stripAudio:
            return stripAudio(query: query, selected: selected, tools: tools, exists: exists)
        case .info(let field):
            if field == .duration || field == .codec || field == .fps {
                return CommandPlan(
                    query: query,
                    summary: "Read \(field.rawValue)",
                    steps: [.fileInfo(field, items: selected, folder: folder)],
                    creates: [],
                    trashes: [],
                    reveal: [],
                    autoRun: true
                )
            }
            let text = FileInfo.report(field: field, items: selected, folder: folder)
            return CommandPlan(
                query: query,
                summary: text,
                steps: [],
                creates: [],
                trashes: [],
                reveal: [],
                autoRun: true,
                readyResult: text
            )
        case .zip:
            return zip(query: query, selected: selected, folder: folder, tools: tools, exists: exists)
        case .unzip:
            return unzip(query: query, selected: selected, tools: tools, exists: exists)
        case .duplicate:
            return duplicate(query: query, selected: selected, exists: exists)
        case .trash:
            return trash(query: query, selected: selected)
        case .openTerminal:
            guard let folder else {
                return fail(query, "No folder to open in Terminal.")
            }
            return CommandPlan(
                query: query,
                summary: "Open Terminal in \(folder.path)",
                steps: [.openTerminal(folder)],
                creates: [],
                trashes: [],
                reveal: [],
                autoRun: true
            )
        case .copyPath:
            let paths = pathList(selected: selected, folder: folder)
            guard !paths.isEmpty else { return fail(query, "Nothing to copy.") }
            return CommandPlan(
                query: query,
                summary: "Copy \(paths.count) path(s) to the clipboard",
                steps: [.copyPasteboard(paths.joined(separator: "\n"))],
                creates: [],
                trashes: [],
                reveal: [],
                autoRun: true
            )
        case .selectAll(let ext):
            return selectMatching(query: query, folder: folder, ext: ext, lastOnly: false)
        case .selectLast(let ext):
            return selectMatching(query: query, folder: folder, ext: ext, lastOnly: true)
        case .mergePDF:
            return planMergePDF(query: query, selected: selected, folder: folder, exists: exists)
        case .splitPDF:
            return planSplitPDF(query: query, selected: selected, folder: folder, exists: exists)
        case .ocr:
            return planOCR(query: query, selected: selected, folder: folder, exists: exists)
        case .renameNumbered:
            return planRenameNumbered(query: query, selected: selected, exists: exists)
        case .renameDatePrefix:
            return planRenameDatePrefix(query: query, selected: selected, exists: exists)
        case .renameCase(let lowercase):
            return planRenameCase(query: query, selected: selected, lowercase: lowercase, exists: exists)
        case .renamePrefix(let prefix):
            return planRenamePrefix(query: query, selected: selected, prefix: prefix, exists: exists)
        case .renameSuffix(let suffix):
            return planRenameSuffix(query: query, selected: selected, suffix: suffix, exists: exists)
        case .renameReplace(let target, let replacement):
            return planRenameReplace(query: query, selected: selected, target: target, replacement: replacement, exists: exists)
        case .organizeByType:
            return organizeByType(query: query, selected: selected, folder: folder, exists: exists)
        }
    }

    private static func convert(
        _ format: OutputFormat,
        query: String,
        selected: [SelectedItem],
        tools: Toolset,
        exists: @escaping (URL) -> Bool
    ) -> CommandPlan {
        let files = selected.filter { !$0.isDirectory }.map(\.url)
        guard !files.isEmpty else { return fail(query, "Select files to convert.") }
        let reserved = PathReservation(base: exists)
        var steps: [PlanStep] = []
        var creates: [URL] = []
        var missing: String?
        for source in files {
            let sourceExt = source.pathExtension.lowercased()
            if sourceExt == format.pathExtension { continue }
            guard let built = convertStep(
                source: source,
                format: format,
                tools: tools,
                exists: { reserved.exists($0) }
            ) else { continue }
            if let tool = built.missing {
                missing = tool
                break
            }
            reserved.take(built.output)
            steps.append(built.step)
            creates.append(built.output)
        }
        if let missing {
            return missingTool(query, missing)
        }
        guard !steps.isEmpty else { return fail(query, "No convertible files in the selection.") }
        return CommandPlan(
            query: query,
            summary: "Convert \(creates.count) file(s) to \(format.pathExtension.uppercased())",
            steps: steps,
            creates: creates,
            trashes: [],
            reveal: creates,
            autoRun: false
        )
    }

    private static func convertStep(
        source: URL,
        format: OutputFormat,
        tools: Toolset,
        exists: @escaping (URL) -> Bool
    ) -> (step: PlanStep, output: URL, missing: String?)? {
        let group = mediaGroup(source.pathExtension)
        let dest = UniqueURL.next(
            in: source.deletingLastPathComponent(),
            name: source.deletingPathExtension().lastPathComponent + ".\(format.pathExtension)",
            exists: exists
        )
        switch (group, format) {
        case (.image, .jpg), (.image, .png), (.image, .heic), (.image, .pdf), (.image, .gif):
            guard let sips = tools.sips else { return ( .process(executable: "", arguments: []), dest, "sips") }
            let sipsFormat: String = switch format {
            case .jpg: "jpeg"
            case .png: "png"
            case .heic: "heic"
            case .pdf: "pdf"
            case .gif: "gif"
            default: "jpeg"
            }
            return (
                .process(executable: sips, arguments: ["-s", "format", sipsFormat, source.path, "--out", dest.path]),
                dest,
                nil
            )
        case (.image, .webp), (.video, .webp):
            guard let ffmpeg = tools.ffmpeg else { return ( .process(executable: "", arguments: []), dest, "ffmpeg") }
            return (
                .process(executable: ffmpeg, arguments: ["-hide_banner", "-nostdin", "-i", source.path, dest.path]),
                dest,
                nil
            )
        case (.video, .mp4), (.image, .mp4):
            guard let ffmpeg = tools.ffmpeg else { return ( .process(executable: "", arguments: []), dest, "ffmpeg") }
            return (
                .process(
                    executable: ffmpeg,
                    arguments: [
                        "-hide_banner", "-nostdin", "-i", source.path,
                        "-c:v", "libx264", "-c:a", "aac", "-pix_fmt", "yuv420p",
                        "-movflags", "+faststart", dest.path,
                    ]
                ),
                dest,
                nil
            )
        case (.video, .gif):
            guard let ffmpeg = tools.ffmpeg else { return ( .process(executable: "", arguments: []), dest, "ffmpeg") }
            return (
                .process(
                    executable: ffmpeg,
                    arguments: [
                        "-hide_banner", "-nostdin", "-i", source.path,
                        "-vf", "fps=12,scale=640:-1", dest.path,
                    ]
                ),
                dest,
                nil
            )
        case (.video, .mp3), (.audio, .mp3), (.video, .wav), (.audio, .wav):
            if format == .wav, group == .audio, let afconvert = tools.afconvert {
                return (
                    .process(
                        executable: afconvert,
                        arguments: ["-f", "WAVE", "-d", "LEI16", source.path, dest.path]
                    ),
                    dest,
                    nil
                )
            }
            guard let ffmpeg = tools.ffmpeg else { return ( .process(executable: "", arguments: []), dest, "ffmpeg") }
            return (
                .process(
                    executable: ffmpeg,
                    arguments: ["-hide_banner", "-nostdin", "-i", source.path, "-vn", dest.path]
                ),
                dest,
                nil
            )
        case (.document, .txt), (.document, .docx):
            guard let textutil = tools.textutil else { return ( .process(executable: "", arguments: []), dest, "textutil") }
            return (
                .process(
                    executable: textutil,
                    arguments: ["-convert", format.pathExtension, "-output", dest.path, source.path]
                ),
                dest,
                nil
            )
        default:
            return nil
        }
    }

    private static func scaleVideo(
        _ height: Int,
        query: String,
        selected: [SelectedItem],
        tools: Toolset,
        exists: @escaping (URL) -> Bool
    ) -> CommandPlan {
        guard let ffmpeg = tools.ffmpeg else { return missingTool(query, "ffmpeg") }
        let videos = selected.map(\.url).filter { mediaGroup($0.pathExtension) == .video }
        guard !videos.isEmpty else { return fail(query, "Select a video.") }
        var steps: [PlanStep] = []
        var creates: [URL] = []
        for source in videos {
            let dest = UniqueURL.next(
                in: source.deletingLastPathComponent(),
                name: source.deletingPathExtension().lastPathComponent + "-\(height)p.mp4",
                exists: exists
            )
            steps.append(
                .process(
                    executable: ffmpeg,
                    arguments: [
                        "-hide_banner", "-nostdin", "-i", source.path,
                        "-vf", "scale=-2:\(height)",
                        "-c:v", "libx264", "-c:a", "aac", dest.path,
                    ]
                )
            )
            creates.append(dest)
        }
        return CommandPlan(
            query: query,
            summary: "Transcode \(creates.count) video(s) to \(height)p",
            steps: steps,
            creates: creates,
            trashes: [],
            reveal: creates,
            autoRun: false
        )
    }

    private static func extractAudio(
        query: String,
        selected: [SelectedItem],
        tools: Toolset,
        exists: @escaping (URL) -> Bool
    ) -> CommandPlan {
        guard let ffmpeg = tools.ffmpeg else { return missingTool(query, "ffmpeg") }
        let sources = selected.map(\.url).filter {
            let g = mediaGroup($0.pathExtension)
            return g == .video || g == .audio
        }
        guard !sources.isEmpty else { return fail(query, "Select a video or audio file.") }
        var steps: [PlanStep] = []
        var creates: [URL] = []
        for source in sources {
            let dest = UniqueURL.next(
                in: source.deletingLastPathComponent(),
                name: source.deletingPathExtension().lastPathComponent + ".m4a",
                exists: exists
            )
            steps.append(
                .process(
                    executable: ffmpeg,
                    arguments: ["-hide_banner", "-nostdin", "-i", source.path, "-vn", "-c:a", "aac", dest.path]
                )
            )
            creates.append(dest)
        }
        return CommandPlan(
            query: query,
            summary: "Extract audio from \(creates.count) file(s)",
            steps: steps,
            creates: creates,
            trashes: [],
            reveal: creates,
            autoRun: false
        )
    }

    private static func stripAudio(
        query: String,
        selected: [SelectedItem],
        tools: Toolset,
        exists: @escaping (URL) -> Bool
    ) -> CommandPlan {
        guard let ffmpeg = tools.ffmpeg else { return missingTool(query, "ffmpeg") }
        let videos = selected.map(\.url).filter { mediaGroup($0.pathExtension) == .video }
        guard !videos.isEmpty else { return fail(query, "Select a video.") }
        var steps: [PlanStep] = []
        var creates: [URL] = []
        for source in videos {
            let dest = UniqueURL.next(
                in: source.deletingLastPathComponent(),
                name: source.deletingPathExtension().lastPathComponent + "-silent.mp4",
                exists: exists
            )
            steps.append(
                .process(
                    executable: ffmpeg,
                    arguments: ["-hide_banner", "-nostdin", "-i", source.path, "-c:v", "copy", "-an", dest.path]
                )
            )
            creates.append(dest)
        }
        return CommandPlan(
            query: query,
            summary: "Strip audio from \(creates.count) video(s)",
            steps: steps,
            creates: creates,
            trashes: [],
            reveal: creates,
            autoRun: false
        )
    }

    private static func zip(
        query: String,
        selected: [SelectedItem],
        folder: URL?,
        tools: Toolset,
        exists: @escaping (URL) -> Bool
    ) -> CommandPlan {
        guard let zip = tools.zip else { return missingTool(query, "zip") }
        let items = selected.map(\.url)
        guard !items.isEmpty else { return fail(query, "Select files to zip.") }
        let parents = Set(items.map { $0.deletingLastPathComponent().standardizedFileURL.path })
        guard parents.count == 1 else {
            return fail(query, "Select files from the same folder to zip.")
        }
        let directory = items[0].deletingLastPathComponent()
        let base = items.count == 1
            ? items[0].deletingPathExtension().lastPathComponent
            : (folder?.lastPathComponent ?? "archive")
        let dest = UniqueURL.next(in: directory, name: "\(base).zip", exists: exists)
        let args = ["-r", dest.lastPathComponent] + items.map(\.lastPathComponent)
        return CommandPlan(
            query: query,
            summary: "Zip \(items.count) item(s) → \(dest.lastPathComponent)",
            steps: [.process(executable: zip, arguments: args)],
            creates: [dest],
            trashes: [],
            reveal: [dest],
            autoRun: false,
            workingDirectory: directory
        )
    }

    private static func unzip(
        query: String,
        selected: [SelectedItem],
        tools: Toolset,
        exists: @escaping (URL) -> Bool
    ) -> CommandPlan {
        guard let ditto = tools.ditto else { return missingTool(query, "ditto") }
        let zips = selected.map(\.url).filter { $0.pathExtension.lowercased() == "zip" }
        guard !zips.isEmpty else { return fail(query, "Select a zip file.") }
        let reserved = PathReservation(base: exists)
        var steps: [PlanStep] = []
        var creates: [URL] = []
        for source in zips {
            let dest = UniqueURL.next(
                in: source.deletingLastPathComponent(),
                name: source.deletingPathExtension().lastPathComponent,
                exists: { reserved.exists($0) }
            )
            reserved.take(dest)
            steps.append(
                .process(executable: ditto, arguments: ["-x", "-k", source.path, dest.path])
            )
            creates.append(dest)
        }
        return CommandPlan(
            query: query,
            summary: "Unzip \(creates.count) archive(s)",
            steps: steps,
            creates: creates,
            trashes: [],
            reveal: creates,
            autoRun: false
        )
    }

    private static func duplicate(
        query: String,
        selected: [SelectedItem],
        exists: @escaping (URL) -> Bool
    ) -> CommandPlan {
        guard !selected.isEmpty else { return fail(query, "Select files to duplicate.") }
        let reserved = PathReservation(base: exists)
        var steps: [PlanStep] = []
        var creates: [URL] = []
        for item in selected {
            let dest = UniqueURL.next(
                in: item.url.deletingLastPathComponent(),
                name: item.url.lastPathComponent,
                exists: { reserved.exists($0) }
            )
            reserved.take(dest)
            steps.append(.copyFile(from: item.url, to: dest))
            creates.append(dest)
        }
        return CommandPlan(
            query: query,
            summary: "Duplicate \(creates.count) item(s)",
            steps: steps,
            creates: creates,
            trashes: [],
            reveal: creates,
            autoRun: false
        )
    }

    private static func trash(query: String, selected: [SelectedItem]) -> CommandPlan {
        guard !selected.isEmpty else { return fail(query, "Select files to move to Trash.") }
        let urls = selected.map(\.url)
        return CommandPlan(
            query: query,
            summary: "Move \(urls.count) item(s) to Trash",
            steps: urls.map { .trash($0) },
            creates: [],
            trashes: urls,
            reveal: [],
            autoRun: false
        )
    }

    private static func selectMatching(
        query: String,
        folder: URL?,
        ext: String,
        lastOnly: Bool
    ) -> CommandPlan {
        guard let folder else { return fail(query, "No folder.") }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let matches = files
            .filter { $0.pathExtension.lowercased() == ext }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !matches.isEmpty else { return fail(query, "No .\(ext) files in this folder.") }
        let chosen = lastOnly ? [matches.last!] : matches
        return CommandPlan(
            query: query,
            summary: lastOnly
                ? "Select last .\(ext)"
                : "Select \(chosen.count) .\(ext) file(s)",
            steps: [.select(chosen)],
            creates: [],
            trashes: [],
            reveal: chosen,
            autoRun: true
        )
    }

    private static func pathList(selected: [SelectedItem], folder: URL?) -> [String] {
        if !selected.isEmpty { return selected.map(\.url.path) }
        if let folder { return [folder.path] }
        return []
    }

    private static func fail(_ query: String, _ message: String) -> CommandPlan {
        CommandPlan(
            query: query,
            summary: message,
            steps: [],
            creates: [],
            trashes: [],
            reveal: [],
            autoRun: false,
            error: message
        )
    }

    private static func missingTool(_ query: String, _ name: String) -> CommandPlan {
        let hint = name == "ffmpeg"
            ? "ffmpeg is not installed. brew install ffmpeg"
            : "\(name) is not available."
        return CommandPlan(
            query: query,
            summary: hint,
            steps: [],
            creates: [],
            trashes: [],
            reveal: [],
            autoRun: false,
            missingTool: name,
            error: hint
        )
    }

    private static func planMergePDF(
        query: String,
        selected: [SelectedItem],
        folder: URL?,
        exists: @escaping (URL) -> Bool
    ) -> CommandPlan {
        let files = selected.filter { !$0.isDirectory }.map(\.url)
        let supported = files.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "pdf" || ["jpg", "jpeg", "png", "heic", "webp", "gif"].contains(ext)
        }
        guard supported.count >= 2 else {
            return fail(query, "Select at least 2 PDF or image files to merge.")
        }
        let targetFolder = folder ?? supported[0].deletingLastPathComponent()
        let dest = UniqueURL.next(in: targetFolder, name: "merged.pdf", exists: exists)
        return CommandPlan(
            query: query,
            summary: "Merge \(supported.count) files into \(dest.lastPathComponent)",
            steps: [.mergePDF(sources: supported, dest: dest)],
            creates: [dest],
            trashes: [],
            reveal: [dest],
            autoRun: false,
            workingDirectory: targetFolder
        )
    }

    private static func planSplitPDF(
        query: String,
        selected: [SelectedItem],
        folder: URL?,
        exists: @escaping (URL) -> Bool
    ) -> CommandPlan {
        let pdfs = selected.filter { !$0.isDirectory && $0.url.pathExtension.lowercased() == "pdf" }.map(\.url)
        guard let first = pdfs.first else {
            return fail(query, "Select a PDF file to split.")
        }
        let targetFolder = folder ?? first.deletingLastPathComponent()
        return CommandPlan(
            query: query,
            summary: "Split \(first.lastPathComponent) into individual pages",
            steps: [.splitPDF(source: first, destFolder: targetFolder)],
            creates: [],
            trashes: [],
            reveal: [],
            autoRun: false,
            workingDirectory: targetFolder
        )
    }

    private static func planOCR(
        query: String,
        selected: [SelectedItem],
        folder: URL?,
        exists: @escaping (URL) -> Bool
    ) -> CommandPlan {
        let files = selected.filter { !$0.isDirectory }.map(\.url).filter { url in
            let ext = url.pathExtension.lowercased()
            return ["png", "jpg", "jpeg", "heic", "webp", "gif", "pdf", "tiff", "bmp"].contains(ext)
        }
        guard !files.isEmpty else {
            return fail(query, "Select an image or PDF file to extract text.")
        }
        let targetFolder = folder ?? files[0].deletingLastPathComponent()
        let destTxt: URL
        if files.count == 1 {
            let baseName = files[0].deletingPathExtension().lastPathComponent
            destTxt = UniqueURL.next(in: targetFolder, name: "\(baseName)_ocr.txt", exists: exists)
        } else {
            destTxt = UniqueURL.next(in: targetFolder, name: "extracted_text.txt", exists: exists)
        }
        return CommandPlan(
            query: query,
            summary: "Extract text (OCR) from \(files.count) file(s)",
            steps: [.ocr(sources: files, destTxt: destTxt, copyToPasteboard: true)],
            creates: [destTxt],
            trashes: [],
            reveal: [destTxt],
            autoRun: true,
            workingDirectory: targetFolder
        )
    }

    private static func renamePlan(
        query: String,
        selected: [SelectedItem],
        exists: @escaping (URL) -> Bool,
        transform: (Int, URL) -> String?
    ) -> CommandPlan {
        let files = selected.filter { !$0.isDirectory }.map(\.url)
        guard !files.isEmpty else {
            return fail(query, "Select files to rename.")
        }
        let reserved = PathReservation(base: exists)
        var steps: [PlanStep] = []
        var reveals: [URL] = []
        for (index, file) in files.enumerated() {
            guard let newName = transform(index, file), !newName.isEmpty else { continue }
            if newName == file.lastPathComponent { continue }
            let parent = file.deletingLastPathComponent()
            let dest = UniqueURL.next(in: parent, name: newName, exists: { reserved.exists($0) })
            reserved.take(dest)
            steps.append(.move(from: file, to: dest))
            reveals.append(dest)
        }
        guard !steps.isEmpty else {
            return fail(query, "No files needed renaming.")
        }
        return CommandPlan(
            query: query,
            summary: "Rename \(steps.count) file(s)",
            steps: steps,
            creates: [],
            trashes: [],
            reveal: reveals,
            autoRun: false
        )
    }

    private static func planRenameNumbered(
        query: String,
        selected: [SelectedItem],
        exists: @escaping (URL) -> Bool
    ) -> CommandPlan {
        let count = selected.filter { !$0.isDirectory }.count
        let digits = max(2, String(count).count)
        return renamePlan(query: query, selected: selected, exists: exists) { index, file in
            let numStr = String(format: "%0\(digits)d", index + 1)
            return "\(numStr)_\(file.lastPathComponent)"
        }
    }

    private static func planRenameDatePrefix(
        query: String,
        selected: [SelectedItem],
        exists: @escaping (URL) -> Bool
    ) -> CommandPlan {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        return renamePlan(query: query, selected: selected, exists: exists) { _, file in
            "\(dateStr)_\(file.lastPathComponent)"
        }
    }

    private static func planRenameCase(
        query: String,
        selected: [SelectedItem],
        lowercase: Bool,
        exists: @escaping (URL) -> Bool
    ) -> CommandPlan {
        return renamePlan(query: query, selected: selected, exists: exists) { _, file in
            let ext = file.pathExtension
            let base = file.deletingPathExtension().lastPathComponent
            let newBase = lowercase ? base.lowercased() : base.uppercased()
            let newExt = lowercase ? ext.lowercased() : ext.uppercased()
            return ext.isEmpty ? newBase : "\(newBase).\(newExt)"
        }
    }

    private static func planRenamePrefix(
        query: String,
        selected: [SelectedItem],
        prefix: String,
        exists: @escaping (URL) -> Bool
    ) -> CommandPlan {
        return renamePlan(query: query, selected: selected, exists: exists) { _, file in
            "\(prefix)\(file.lastPathComponent)"
        }
    }

    private static func planRenameSuffix(
        query: String,
        selected: [SelectedItem],
        suffix: String,
        exists: @escaping (URL) -> Bool
    ) -> CommandPlan {
        return renamePlan(query: query, selected: selected, exists: exists) { _, file in
            let ext = file.pathExtension
            let base = file.deletingPathExtension().lastPathComponent
            return ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)"
        }
    }

    private static func planRenameReplace(
        query: String,
        selected: [SelectedItem],
        target: String,
        replacement: String,
        exists: @escaping (URL) -> Bool
    ) -> CommandPlan {
        return renamePlan(query: query, selected: selected, exists: exists) { _, file in
            let name = file.lastPathComponent
            if name.contains(target) {
                return name.replacingOccurrences(of: target, with: replacement)
            }
            return nil
        }
    }

    private static func organizeByType(
        query: String,
        selected: [SelectedItem],
        folder: URL?,
        exists: @escaping (URL) -> Bool
    ) -> CommandPlan {
        let picked = selected.filter { !$0.isDirectory }.map(\.url)
        let files: [URL]
        if picked.count >= 2 {
            files = picked
        } else if let folder {
            files = looseFiles(in: folder)
        } else {
            files = picked
        }
        let sources = files.filter { !$0.lastPathComponent.hasPrefix("~$") }
        guard !sources.isEmpty else { return fail(query, "No files to organize.") }
        let reserved = PathReservation(base: exists)
        var steps: [PlanStep] = []
        var groups = Set<String>()
        for file in sources {
            let group = file.pathExtension.isEmpty ? "Other" : file.pathExtension.uppercased()
            groups.insert(group)
            let directory = file.deletingLastPathComponent().appendingPathComponent(group, isDirectory: true)
            let dest = UniqueURL.next(in: directory, name: file.lastPathComponent, exists: { reserved.exists($0) })
            reserved.take(dest)
            steps.append(.move(from: file, to: dest))
        }
        return CommandPlan(
            query: query,
            summary: "Move \(steps.count) files into \(groups.count) folders by type",
            steps: steps,
            creates: [],
            trashes: [],
            reveal: [],
            autoRun: false
        )
    }

    private static func looseFiles(in folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { url in
            let dir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return !dir
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private final class PathReservation {
        private var taken = Set<String>()
        private let base: (URL) -> Bool

        init(base: @escaping (URL) -> Bool) {
            self.base = base
        }

        func exists(_ url: URL) -> Bool {
            taken.contains(url.path) || base(url)
        }

        func take(_ url: URL) {
            taken.insert(url.path)
        }
    }

    private enum MediaGroup {
        case image, video, audio, document, other
    }

    private static func mediaGroup(_ ext: String) -> MediaGroup {
        switch ext.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp":
            return .image
        case "mp4", "mov", "m4v", "mkv", "avi", "webm":
            return .video
        case "mp3", "wav", "m4a", "aac", "aiff", "caf", "flac":
            return .audio
        case "txt", "rtf", "doc", "docx", "md", "html":
            return .document
        default:
            return .other
        }
    }
}
