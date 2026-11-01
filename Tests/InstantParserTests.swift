import XCTest
@testable import Understage

final class InstantParserTests: XCTestCase {
    func testFormatsEnglishAndChinese() {
        XCTAssertEqual(InstantParser.parse("jpg"), .convert(.jpg))
        XCTAssertEqual(InstantParser.parse("convert to png"), .convert(.png))
        XCTAssertEqual(InstantParser.parse("转成 mp4"), .convert(.mp4))
        XCTAssertEqual(InstantParser.parse("make a jpg please"), .convert(.jpg))
        XCTAssertEqual(InstantParser.parse("纯文本"), .convert(.txt))
        XCTAssertEqual(InstantParser.parse("word doc"), .convert(.docx))
    }

    func testMediaAndInfo() {
        XCTAssertEqual(InstantParser.parse("hevc 720p"), .encodeHEVC(height: 720))
        XCTAssertEqual(InstantParser.parse("h265"), .encodeHEVC(height: nil))
        XCTAssertEqual(InstantParser.parse("1080p"), .scaleVideo(height: 1080))
        XCTAssertEqual(InstantParser.parse("convert to 1080p"), .scaleVideo(height: 1080))
        XCTAssertNil(InstantParser.parse("1080p 并抽出音频"))
        XCTAssertEqual(InstantParser.parse("提取音频"), .extractAudio)
        XCTAssertEqual(InstantParser.parse("去音频"), .stripAudio)
        XCTAssertEqual(InstantParser.parse("词数"), .info(.wordCount))
        XCTAssertEqual(InstantParser.parse("字数"), .info(.charCount))
        XCTAssertEqual(InstantParser.parse("word count"), .info(.wordCount))
        XCTAssertEqual(InstantParser.parse("大小"), .info(.size))
        XCTAssertEqual(InstantParser.parse("路径"), .info(.path))
        XCTAssertEqual(InstantParser.parse("type"), .info(.fileType))
        XCTAssertEqual(
            InstantParser.parse("根据文件类型移动到不同的文件夹中"),
            .organizeByType
        )
        XCTAssertEqual(
            InstantParser.parse("sort the files into different folders according to their type"),
            .organizeByType
        )
        XCTAssertEqual(
            InstantParser.parse("整理这些文件到不同类型的文件夹中"),
            .organizeByType
        )
        XCTAssertEqual(InstantParser.parse("copy path"), .copyPath)
    }

    func testManagement() {
        XCTAssertEqual(InstantParser.parse("zip"), .zip)
        XCTAssertEqual(InstantParser.parse("压缩"), .zip)
        XCTAssertEqual(InstantParser.parse("解压"), .unzip)
        XCTAssertEqual(InstantParser.parse("副本"), .duplicate)
        XCTAssertEqual(InstantParser.parse("废纸篓"), .trash)
        XCTAssertEqual(InstantParser.parse("term"), .openTerminal)
        XCTAssertEqual(InstantParser.parse("打开终端"), .openTerminal)
    }

    func testSelect() {
        XCTAssertEqual(InstantParser.parse("select all pdfs"), .selectAll(ext: "pdf"))
        XCTAssertEqual(InstantParser.parse("选中所有 jpg"), .selectAll(ext: "jpg"))
        XCTAssertEqual(InstantParser.parse("select last word doc"), .selectLast(ext: "docx"))
        XCTAssertEqual(InstantParser.parse("选中最后一个 png"), .selectLast(ext: "png"))
    }

    func testPDFAndOCRAndRenameParsing() {
        XCTAssertEqual(InstantParser.parse("merge pdf"), .mergePDF)
        XCTAssertEqual(InstantParser.parse("合并 pdf"), .mergePDF)
        XCTAssertEqual(InstantParser.parse("合并为pdf"), .mergePDF)
        XCTAssertEqual(InstantParser.parse("split pdf"), .splitPDF)
        XCTAssertEqual(InstantParser.parse("拆分 pdf"), .splitPDF)
        XCTAssertEqual(InstantParser.parse("ocr"), .ocr)
        XCTAssertEqual(InstantParser.parse("提取文字"), .ocr)
        XCTAssertEqual(InstantParser.parse("1 2 3"), .renameNumbered)
        XCTAssertEqual(InstantParser.parse("序号"), .renameNumbered)
        XCTAssertEqual(InstantParser.parse("加日期"), .renameDatePrefix)
        XCTAssertEqual(InstantParser.parse("date prefix"), .renameDatePrefix)
        XCTAssertEqual(InstantParser.parse("转小写"), .renameCase(lowercase: true))
        XCTAssertEqual(InstantParser.parse("lowercase"), .renameCase(lowercase: true))
        XCTAssertEqual(InstantParser.parse("转大写"), .renameCase(lowercase: false))
        XCTAssertEqual(InstantParser.parse("uppercase"), .renameCase(lowercase: false))
        XCTAssertEqual(InstantParser.parse("prefix v1_"), .renamePrefix("v1_"))
        XCTAssertEqual(InstantParser.parse("加前缀 draft_"), .renamePrefix("draft_"))
        XCTAssertEqual(InstantParser.parse("suffix _backup"), .renameSuffix("_backup"))
        XCTAssertEqual(InstantParser.parse("加后缀 _old"), .renameSuffix("_old"))
        XCTAssertEqual(InstantParser.parse("replace draft with final"), .renameReplace(target: "draft", replacement: "final"))
        XCTAssertEqual(InstantParser.parse("把 img 替换为 photo"), .renameReplace(target: "img", replacement: "photo"))
    }

    func testUnknownIsNil() {
        XCTAssertNil(InstantParser.parse("organize these by date"))
        XCTAssertNil(InstantParser.parse(""))
    }
}

final class UniqueURLTests: XCTestCase {
    func testIncrementsUntilFree() {
        let dir = URL(fileURLWithPath: "/tmp")
        var taken: Set<String> = ["/tmp/photo.jpg"]
        let first = UniqueURL.next(in: dir, name: "photo.jpg") { taken.contains($0.path) }
        XCTAssertEqual(first.lastPathComponent, "photo_1.jpg")
        taken.insert(first.path)
        let second = UniqueURL.next(in: dir, name: "photo.jpg") { taken.contains($0.path) }
        XCTAssertEqual(second.lastPathComponent, "photo_2.jpg")
    }
}

final class CommandPlannerTests: XCTestCase {
    private let tools = Toolset(
        ffmpeg: "/opt/homebrew/bin/ffmpeg",
        sips: "/usr/bin/sips",
        afconvert: "/usr/bin/afconvert",
        textutil: "/usr/bin/textutil",
        zip: "/usr/bin/zip",
        ditto: "/usr/bin/ditto"
    )

    private func item(_ path: String, directory: Bool = false) -> SelectedItem {
        let url = URL(fileURLWithPath: path)
        return SelectedItem(url: url, name: url.lastPathComponent, isDirectory: directory)
    }

    func testHEVC720UsesInstalledFfmpeg() {
        let plan = CommandPlanner.plan(
            action: .encodeHEVC(height: 720),
            query: "hevc 720p",
            selected: [item("/tmp/clip.mp4")],
            folder: URL(fileURLWithPath: "/tmp"),
            tools: tools
        )
        XCTAssertNil(plan.error)
        guard case .process(let exe, let args) = plan.steps.first else {
            return XCTFail("expected ffmpeg")
        }
        XCTAssertEqual(exe, "/opt/homebrew/bin/ffmpeg")
        XCTAssertTrue(args.contains("hevc_videotoolbox"))
        XCTAssertTrue(args.contains("scale=-2:720"))
    }

    func testJpgPlanUsesSipsAndDoesNotOverwrite() {
        let selected = [item("/tmp/shot.png")]
        let plan = CommandPlanner.plan(
            action: .convert(.jpg),
            query: "jpg",
            selected: selected,
            folder: URL(fileURLWithPath: "/tmp"),
            tools: tools,
            exists: { $0.path == "/tmp/shot.jpg" }
        )
        XCTAssertNil(plan.error)
        XCTAssertFalse(plan.autoRun)
        XCTAssertEqual(plan.creates.map(\.lastPathComponent), ["shot_1.jpg"])
        guard case .process(let exe, let args) = plan.steps.first else {
            return XCTFail("expected sips")
        }
        XCTAssertEqual(exe, "/usr/bin/sips")
        XCTAssertTrue(args.contains("jpeg"))
        XCTAssertTrue(args.contains("/tmp/shot.png"))
    }

    func testMp4WithoutFfmpegReportsMissingTool() {
        var noFFmpeg = tools
        noFFmpeg.ffmpeg = nil
        let plan = CommandPlanner.plan(
            action: .convert(.mp4),
            query: "mp4",
            selected: [item("/tmp/clip.mov")],
            folder: URL(fileURLWithPath: "/tmp"),
            tools: noFFmpeg
        )
        XCTAssertEqual(plan.missingTool, "ffmpeg")
        XCTAssertTrue(plan.steps.isEmpty)
    }

    func testTrashIsNeverAutoRun() {
        let plan = CommandPlanner.plan(
            action: .trash,
            query: "trash",
            selected: [item("/tmp/shot.png")],
            folder: URL(fileURLWithPath: "/tmp"),
            tools: tools
        )
        XCTAssertFalse(plan.autoRun)
        XCTAssertEqual(plan.trashes.count, 1)
    }

    func testInfoAutoRuns() {
        let plan = CommandPlanner.plan(
            action: .info(.path),
            query: "path",
            selected: [item("/tmp/shot.png")],
            folder: URL(fileURLWithPath: "/tmp"),
            tools: tools
        )
        XCTAssertTrue(plan.autoRun)
        XCTAssertTrue(plan.readyResult?.contains("/tmp/shot.png") == true)
    }

    func testSkipSameFormat() {
        let plan = CommandPlanner.plan(
            action: .convert(.png),
            query: "png",
            selected: [item("/tmp/shot.png")],
            folder: URL(fileURLWithPath: "/tmp"),
            tools: tools
        )
        XCTAssertEqual(plan.error, L10n.tr("No convertible files in the selection."))
    }

    func testPDFMergePlanner() {
        let selected = [item("/tmp/a.pdf"), item("/tmp/b.pdf")]
        let plan = CommandPlanner.plan(
            action: .mergePDF,
            query: "merge pdf",
            selected: selected,
            folder: URL(fileURLWithPath: "/tmp"),
            tools: tools
        )
        XCTAssertNil(plan.error)
        XCTAssertEqual(plan.creates.map(\.lastPathComponent), ["merged.pdf"])
        guard case .mergePDF(let sources, let dest) = plan.steps.first else {
            return XCTFail("expected mergePDF step")
        }
        XCTAssertEqual(sources.count, 2)
        XCTAssertEqual(dest.lastPathComponent, "merged.pdf")
    }

    func testPDFSplitPlanner() {
        let selected = [item("/tmp/doc.pdf")]
        let plan = CommandPlanner.plan(
            action: .splitPDF,
            query: "split pdf",
            selected: selected,
            folder: URL(fileURLWithPath: "/tmp"),
            tools: tools
        )
        XCTAssertNil(plan.error)
        guard case .splitPDF(let source, _) = plan.steps.first else {
            return XCTFail("expected splitPDF step")
        }
        XCTAssertEqual(source.lastPathComponent, "doc.pdf")
    }

    func testOCRPlanner() {
        let selected = [item("/tmp/scan.png")]
        let plan = CommandPlanner.plan(
            action: .ocr,
            query: "ocr",
            selected: selected,
            folder: URL(fileURLWithPath: "/tmp"),
            tools: tools
        )
        XCTAssertNil(plan.error)
        XCTAssertTrue(plan.autoRun)
        XCTAssertEqual(plan.creates.map(\.lastPathComponent), ["scan_ocr.txt"])
        guard case .ocr(let sources, let dest, true) = plan.steps.first else {
            return XCTFail("expected ocr step")
        }
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(dest?.lastPathComponent, "scan_ocr.txt")
    }

    func testBatchRenamePlanner() {
        let selected = [item("/tmp/apple.jpg"), item("/tmp/banana.jpg")]

        let planNumbered = CommandPlanner.plan(
            action: .renameNumbered,
            query: "1 2 3",
            selected: selected,
            folder: URL(fileURLWithPath: "/tmp"),
            tools: tools
        )
        XCTAssertEqual(planNumbered.steps.count, 2)
        guard case .move(_, let to1) = planNumbered.steps[0],
              case .move(_, let to2) = planNumbered.steps[1] else {
            return XCTFail("expected move steps")
        }
        XCTAssertEqual(to1.lastPathComponent, "01_apple.jpg")
        XCTAssertEqual(to2.lastPathComponent, "02_banana.jpg")

        let planPrefix = CommandPlanner.plan(
            action: .renamePrefix("fruit_"),
            query: "prefix fruit_",
            selected: selected,
            folder: URL(fileURLWithPath: "/tmp"),
            tools: tools
        )
        guard case .move(_, let toPrefix) = planPrefix.steps.first else {
            return XCTFail("expected move step")
        }
        XCTAssertEqual(toPrefix.lastPathComponent, "fruit_apple.jpg")

        let planSuffix = CommandPlanner.plan(
            action: .renameSuffix("_raw"),
            query: "suffix _raw",
            selected: selected,
            folder: URL(fileURLWithPath: "/tmp"),
            tools: tools
        )
        guard case .move(_, let toSuffix) = planSuffix.steps.first else {
            return XCTFail("expected move step")
        }
        XCTAssertEqual(toSuffix.lastPathComponent, "apple_raw.jpg")

        let planReplace = CommandPlanner.plan(
            action: .renameReplace(target: "apple", replacement: "orange"),
            query: "replace apple with orange",
            selected: selected,
            folder: URL(fileURLWithPath: "/tmp"),
            tools: tools
        )
        XCTAssertEqual(planReplace.steps.count, 1)
        guard case .move(_, let toReplace) = planReplace.steps.first else {
            return XCTFail("expected move step")
        }
        XCTAssertEqual(toReplace.lastPathComponent, "orange.jpg")
    }

    func testSameBasenameConvertsDoNotCollide() {
        let selected = [item("/tmp/photo.png"), item("/tmp/photo.heic")]
        let plan = CommandPlanner.plan(
            action: .convert(.jpg),
            query: "jpg",
            selected: selected,
            folder: URL(fileURLWithPath: "/tmp"),
            tools: tools,
            exists: { _ in false }
        )
        XCTAssertEqual(Set(plan.creates.map(\.lastPathComponent)), ["photo.jpg", "photo_1.jpg"])
    }

    func testOrganizeByTypePlansEveryFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("understage-sort-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["a.pdf", "b.pdf", "c.docx"] {
            try "x".write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let plan = CommandPlanner.plan(
            action: .organizeByType,
            query: "根据文件类型移动到不同的文件夹中",
            selected: [],
            folder: dir,
            tools: tools
        )
        XCTAssertEqual(plan.steps.count, 3)
        XCTAssertEqual(plan.summary, L10n.format("Move %ld files into %@", 3, "文档"))
        XCTAssertFalse(plan.autoRun)
        let dests = plan.steps.compactMap { step -> String? in
            if case .move(_, let to) = step { return to.path }
            return nil
        }
        XCTAssertTrue(dests.contains { $0.hasSuffix("/文档/a.pdf") })
        XCTAssertTrue(dests.contains { $0.hasSuffix("/文档/b.pdf") })
        XCTAssertTrue(dests.contains { $0.hasSuffix("/文档/c.docx") })
    }

    func testZipRefusesMixedFolders() {
        let plan = CommandPlanner.plan(
            action: .zip,
            query: "zip",
            selected: [item("/tmp/a/one.png"), item("/tmp/b/two.png")],
            folder: URL(fileURLWithPath: "/tmp"),
            tools: tools
        )
        XCTAssertEqual(plan.error, L10n.tr("Select files from the same folder to zip."))
    }

    func testCharacterCountSkipsWhitespace() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("understage-chars-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("note.txt")
        try "你好 world".write(to: file, atomically: true, encoding: .utf8)
        let text = FileInfo.report(
            field: .charCount,
            items: [item(file.path)],
            folder: dir
        )
        XCTAssertTrue(text.contains(L10n.format("%ld chars", 7)))
    }
}
