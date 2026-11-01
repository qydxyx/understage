import XCTest
@testable import Understage

final class AgentParserTests: XCTestCase {
    func testParsesListAndRun() throws {
        let list = try AgentParser.parse(#"{"tool":"list","path":"/tmp/demo"}"#)
        XCTAssertEqual(list.tool, .list)
        XCTAssertEqual(list.path, "/tmp/demo")

        let run = try AgentParser.parse(
            #"{"tool":"run","executable":"/usr/bin/sips","arguments":["-s","format","jpeg"],"summary":"jpg","creates":["/tmp/a.jpg"]}"#
        )
        XCTAssertEqual(run.tool, .run)
        XCTAssertEqual(run.executable, "/usr/bin/sips")
        XCTAssertEqual(run.creates.first?.path, "/tmp/a.jpg")
    }

    func testRejectsUnknownTool() {
        XCTAssertThrowsError(try AgentParser.parse(#"{"tool":"explode"}"#))
    }

    func testAskUserKeepsOptions() throws {
        let call = try AgentParser.parse(
            #"{"tool":"ask_user","question":"How should these be grouped?","options":["By extension","By purpose"]}"#
        )
        XCTAssertEqual(call.tool, .askUser)
        XCTAssertEqual(call.options, ["By extension", "By purpose"])
    }

    func testOrganizeWithoutChangesIsNotSuccess() {
        let finished = AgentFinish.result(
            query: "整理这些文件，分门别类到不同的文件夹",
            summary: "已成功分类整理下载文件夹中的文件。",
            mutated: false
        )
        XCTAssertFalse(finished.ok)
        XCTAssertTrue(finished.text.contains("没有改动任何文件"))
        let partial = AgentFinish.result(
            query: "根据文件类型移动到不同的文件夹中",
            summary: "已成功将文件移动到分类文件夹中。",
            mutated: true,
            filesLeft: 40
        )
        XCTAssertFalse(partial.ok)
        XCTAssertTrue(partial.text.contains("40"))
    }

    func testJoinCollapsesDoubleSlash() throws {
        let base = try XCTUnwrap(URL(string: "https://llm.example:444//v1"))
        let url = join(base, "chat/completions")
        XCTAssertEqual(url.absoluteString, "https://llm.example:444/v1/chat/completions")
    }
}

final class SkillCatalogTests: XCTestCase {
    func testParsesFrontMatterAndMatch() {
        let skill = SkillCatalog.parse(
            """
            ---
            id: ffmpeg
            title: FFmpeg recipes
            match: mp4,mov
            ---
            Use scale=-2:1080
            """,
            fallbackID: "x"
        )
        XCTAssertEqual(skill.id, "ffmpeg")
        XCTAssertTrue(skill.matches(extensions: ["mp4"]))
        XCTAssertFalse(skill.matches(extensions: ["png"]))
        XCTAssertTrue(skill.body.contains("1080"))
    }
}

final class AgentToolsTests: XCTestCase {
    func testWorkspaceAndList() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("understage-agent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "hi".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        XCTAssertTrue(AgentTools.inWorkspace(dir.appendingPathComponent("a.txt"), folder: dir, selected: []))
        XCTAssertFalse(
            AgentTools.inWorkspace(URL(fileURLWithPath: "/etc/passwd"), folder: dir, selected: [])
        )
        let listing = try AgentTools.list(path: dir)
        XCTAssertTrue(listing.contains("a.txt"))
    }

    func testMoveBatchIsOnePlan() throws {
        let call = try AgentParser.parse(
            #"{"tool":"move","summary":"by type","moves":[{"from":"/tmp/understage-ws/a.txt","to":"/tmp/understage-ws/TXT/a.txt"},{"from":"/tmp/understage-ws/b.pdf","to":"/tmp/understage-ws/PDF/b.pdf"}]}"#
        )
        XCTAssertEqual(call.moves.count, 2)
        let plan = try AgentTools.plan(
            from: call,
            query: "整理",
            folder: URL(fileURLWithPath: "/tmp/understage-ws"),
            selected: [],
            autoRun: .init()
        )
        XCTAssertEqual(plan.steps.count, 2)
        XCTAssertTrue(plan.reveal.isEmpty)
        XCTAssertTrue(plan.autoRun)
    }

    func testMovePlanStaysInFolder() throws {
        let dir = URL(fileURLWithPath: "/tmp/understage-ws")
        let call = AgentCall(
            tool: .move,
            summary: "rename",
            path: nil,
            paths: [],
            executable: nil,
            arguments: [],
            creates: [],
            from: "/tmp/understage-ws/a.txt",
            to: "/tmp/understage-ws/b.txt",
            question: nil
        )
        let plan = try AgentTools.plan(
            from: call,
            query: "rename",
            folder: dir,
            selected: [],
            autoRun: AutoRunSettings(readOnly: true, fileChanges: true)
        )
        XCTAssertTrue(plan.autoRun)
        guard case .move(let from, let to) = plan.steps.first else {
            return XCTFail("expected move")
        }
        XCTAssertEqual(from.lastPathComponent, "a.txt")
        XCTAssertEqual(to.lastPathComponent, "b.txt")
    }
}

final class UndoActionTests: XCTestCase {
    func testTrashCreatedThenUndo() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("understage-undo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("made.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        try UndoAction.trashCreated(file.path).apply()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testMoveBack() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("understage-undo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.txt")
        let b = dir.appendingPathComponent("b.txt")
        try "x".write(to: a, atomically: true, encoding: .utf8)
        try FileManager.default.moveItem(at: a, to: b)
        try UndoAction.moveBack(from: b.path, to: a.path).apply()
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.path))
    }

    func testFailedUndoActionStaysInTheBatch() {
        let missing = "/tmp/understage-missing-\(UUID().uuidString)"
        let outcome = UndoJournal.apply([.trashCreated(missing)])
        XCTAssertEqual(outcome.remaining.count, 1)
        XCTAssertFalse(outcome.errors.isEmpty)
    }
}
