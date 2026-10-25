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
        XCTAssertEqual(InstantParser.parse("1080p"), .scaleVideo(height: 1080))
        XCTAssertEqual(InstantParser.parse("convert to 1080p mp4"), .scaleVideo(height: 1080))
        XCTAssertEqual(InstantParser.parse("提取音频"), .extractAudio)
        XCTAssertEqual(InstantParser.parse("去音频"), .stripAudio)
        XCTAssertEqual(InstantParser.parse("词数"), .info(.wordCount))
        XCTAssertEqual(InstantParser.parse("word count"), .info(.wordCount))
        XCTAssertEqual(InstantParser.parse("大小"), .info(.size))
        XCTAssertEqual(InstantParser.parse("路径"), .info(.path))
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
        XCTAssertEqual(plan.error, "No convertible files in the selection.")
    }
}
