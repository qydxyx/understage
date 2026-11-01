import XCTest
import PDFKit
@testable import Understage

final class CommandRunnerTests: XCTestCase {
    func testSipsJpegConversionKeepsOriginal() async throws {
        guard let sips = ToolDetector.which("sips") else {
            throw XCTSkip("sips missing")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("understage-m1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("shot.png")
        try Self.png1x1.write(to: source)
        let selected = [SelectedItem(url: source, name: "shot.png", isDirectory: false)]
        let tools = Toolset(
            ffmpeg: nil,
            sips: sips,
            afconvert: nil,
            textutil: nil,
            zip: nil,
            ditto: nil
        )
        let plan = CommandPlanner.plan(
            action: .convert(.jpg),
            query: "jpg",
            selected: selected,
            folder: dir,
            tools: tools
        )
        XCTAssertEqual(plan.creates.count, 1)
        let outcome = await CommandRunner.run(plan, session: CommandRunner.Session())
        guard case .success = outcome else {
            return XCTFail("\(outcome)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.creates[0].path))
        XCTAssertEqual(plan.creates[0].pathExtension, "jpg")
    }

    func testPDFMergeAndSplitLive() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("understage-pdf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create two 1-page PDFs using valid bitmap image
        guard let img = NSImage(data: Self.png1x1),
              let page1 = PDFPage(image: img),
              let page2 = PDFPage(image: img) else {
            return XCTFail("Failed to create PDFPage from valid test image")
        }

        let pdf1 = PDFDocument()
        pdf1.insert(page1, at: 0)
        let file1 = dir.appendingPathComponent("doc1.pdf")
        XCTAssertTrue(pdf1.write(to: file1))

        let pdf2 = PDFDocument()
        pdf2.insert(page2, at: 0)
        let file2 = dir.appendingPathComponent("doc2.pdf")
        XCTAssertTrue(pdf2.write(to: file2))

        let selected = [
            SelectedItem(url: file1, name: "doc1.pdf", isDirectory: false),
            SelectedItem(url: file2, name: "doc2.pdf", isDirectory: false),
        ]

        // 1. Merge
        let mergePlan = CommandPlanner.plan(
            action: .mergePDF,
            query: "merge pdf",
            selected: selected,
            folder: dir,
            tools: .system
        )
        let mergeOutcome = await CommandRunner.run(mergePlan, session: CommandRunner.Session())
        guard case .success = mergeOutcome else {
            return XCTFail("merge failed: \(mergeOutcome)")
        }
        let mergedFile = dir.appendingPathComponent("merged.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: mergedFile.path))
        let mergedDoc = PDFDocument(url: mergedFile)
        XCTAssertEqual(mergedDoc?.pageCount, 2)

        // 2. Split
        let splitSelected = [SelectedItem(url: mergedFile, name: "merged.pdf", isDirectory: false)]
        let splitPlan = CommandPlanner.plan(
            action: .splitPDF,
            query: "split pdf",
            selected: splitSelected,
            folder: dir,
            tools: .system
        )
        let splitOutcome = await CommandRunner.run(splitPlan, session: CommandRunner.Session())
        guard case .success = splitOutcome else {
            return XCTFail("split failed: \(splitOutcome)")
        }
        let splitPage1 = dir.appendingPathComponent("merged_page_1.pdf")
        let splitPage2 = dir.appendingPathComponent("merged_page_2.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: splitPage1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: splitPage2.path))
    }

    func testBatchRenameAndUndoLive() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("understage-rename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileA = dir.appendingPathComponent("alpha.txt")
        let fileB = dir.appendingPathComponent("beta.txt")
        try "hello".write(to: fileA, atomically: true, encoding: .utf8)
        try "world".write(to: fileB, atomically: true, encoding: .utf8)

        let selected = [
            SelectedItem(url: fileA, name: "alpha.txt", isDirectory: false),
            SelectedItem(url: fileB, name: "beta.txt", isDirectory: false),
        ]

        let plan = CommandPlanner.plan(
            action: .renameNumbered,
            query: "1 2 3",
            selected: selected,
            folder: dir,
            tools: .system
        )
        let report = await CommandRunner.runWithUndo(plan, session: CommandRunner.Session())
        guard case .success = report.outcome else {
            return XCTFail("rename failed: \(report.outcome)")
        }

        let newA = dir.appendingPathComponent("01_alpha.txt")
        let newB = dir.appendingPathComponent("02_beta.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: newA.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newB.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileA.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileB.path))

        // Record to UndoJournal and test undo
        await MainActor.run {
            UndoJournal.shared.record(query: plan.query, summary: plan.summary, actions: report.undos)
            _ = UndoJournal.shared.undoLast()
        }

        // Verify restored
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileA.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileB.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newA.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newB.path))
    }

    func testCancelIsNotSuccess() async {
        let plan = CommandPlan(
            query: "sleep",
            summary: "sleep",
            steps: [.process(executable: "/bin/sleep", arguments: ["30"])],
            creates: [],
            trashes: [],
            reveal: [],
            autoRun: false
        )
        let session = CommandRunner.Session()
        let task = Task { await CommandRunner.runWithUndo(plan, session: session) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        session.cancel()
        let report = await task.value
        guard case .cancelled = report.outcome else {
            return XCTFail("expected cancelled, got \(report.outcome)")
        }
    }

    func testPartialFailureKeepsEarlierUndo() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("understage-partial-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("a.txt")
        try "x".write(to: source, atomically: true, encoding: .utf8)
        let dest = dir.appendingPathComponent("b.txt")
        let plan = CommandPlan(
            query: "copy",
            summary: "copy",
            steps: [
                .copyFile(from: source, to: dest),
                .process(executable: "/usr/bin/false", arguments: []),
            ],
            creates: [dest],
            trashes: [],
            reveal: [],
            autoRun: false
        )
        let report = await CommandRunner.runWithUndo(plan, session: CommandRunner.Session())
        guard case .failure = report.outcome else {
            return XCTFail("expected failure, got \(report.outcome)")
        }
        XCTAssertTrue(report.undos.contains { action in
            if case .trashCreated(let path) = action { return path == dest.path }
            return false
        })
    }

    func testCaseOnlyRename() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("understage-case-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("Photo.TXT")
        try "x".write(to: source, atomically: true, encoding: .utf8)
        let dest = dir.appendingPathComponent("photo.txt")
        let plan = CommandPlan(
            query: "lowercase",
            summary: "lowercase",
            steps: [.move(from: source, to: dest)],
            creates: [],
            trashes: [],
            reveal: [dest],
            autoRun: false
        )
        let report = await CommandRunner.runWithUndo(plan, session: CommandRunner.Session())
        guard case .success = report.outcome else {
            return XCTFail("expected success, got \(report.outcome)")
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains("photo.txt"))
        XCTAssertFalse(names.contains("Photo.TXT"))
    }

    func testMoveCreatesMissingFolder() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("understage-mkdir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("note.txt")
        try "x".write(to: source, atomically: true, encoding: .utf8)
        let dest = dir.appendingPathComponent("Docs").appendingPathComponent("note.txt")
        let plan = CommandPlan(
            query: "move",
            summary: "move",
            steps: [.move(from: source, to: dest)],
            creates: [dest],
            trashes: [],
            reveal: [],
            autoRun: false
        )
        let report = await CommandRunner.runWithUndo(plan, session: CommandRunner.Session())
        guard case .success = report.outcome else {
            return XCTFail("expected success, got \(report.outcome)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(names.contains("note.txt"))
    }

    func testOrganizeByTypeMovesEveryFile() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("understage-org-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["one.pdf", "two.pdf", "note.docx", "clip.mp4", "readme"] {
            try "x".write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Keep"), withIntermediateDirectories: true)
        let query = "根据文件类型移动到不同的文件夹中"
        let action = try XCTUnwrap(InstantParser.parse(query))
        XCTAssertEqual(action, .organizeByType)
        let plan = CommandPlanner.plan(
            action: action,
            query: query,
            selected: [],
            folder: dir,
            tools: .system
        )
        XCTAssertEqual(plan.steps.count, 5)
        XCTAssertFalse(plan.autoRun)
        let report = await CommandRunner.runWithUndo(plan, session: CommandRunner.Session())
        guard case .success = report.outcome else {
            return XCTFail("expected success, got \(report.outcome)")
        }
        XCTAssertEqual(report.undos.count, 5)
        let root = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(root.contains("one.pdf"))
        XCTAssertFalse(root.contains("note.docx"))
        XCTAssertFalse(root.contains("clip.mp4"))
        XCTAssertFalse(root.contains("readme"))
        XCTAssertTrue(root.contains("Keep"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("PDF/one.pdf").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("PDF/two.pdf").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("DOCX/note.docx").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("MP4/clip.mp4").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Other/readme").path))
    }

    /// 1×1 gray PNG.
    private static let png1x1 = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII="
    )!
}
