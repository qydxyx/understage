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
            autoRun: AutoRunSettings(readOnly: true, create: false)
        )
        XCTAssertFalse(plan.autoRun)
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
}
