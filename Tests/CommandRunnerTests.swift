import XCTest
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

    /// 1×1 gray PNG.
    private static let png1x1 = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII="
    )!
}
