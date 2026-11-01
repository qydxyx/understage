import XCTest
@testable import Understage

final class PredictorTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/Users/demo/Documents")
    private let file = URL(fileURLWithPath: "/Users/demo/Documents/a.png")

    func testSipsIsCreate() {
        let plan = CommandPlan(
            query: "jpg",
            summary: "convert",
            steps: [
                .process(
                    executable: "/usr/bin/sips",
                    arguments: ["-s", "format", "jpeg", file.path, "--out", "/Users/demo/Documents/a.jpg"]
                ),
            ],
            creates: [URL(fileURLWithPath: "/Users/demo/Documents/a.jpg")],
            trashes: [],
            reveal: [],
            autoRun: false
        )
        let prediction = Predictor.analyze(plan: plan, folder: folder, selected: [file])
        XCTAssertEqual(prediction.risk, .create)
        XCTAssertTrue(AutoRunPolicy.allows(prediction, settings: AutoRunSettings(readOnly: true, create: true)))
        XCTAssertFalse(AutoRunPolicy.allows(prediction, settings: AutoRunSettings(readOnly: true, create: false)))
    }

    func testSudoIsForbidden() {
        let plan = CommandPlan(
            query: "sudo",
            summary: "no",
            steps: [
                .process(executable: "/usr/bin/sudo", arguments: ["rm", "-rf", file.path]),
            ],
            creates: [],
            trashes: [],
            reveal: [],
            autoRun: false
        )
        let prediction = Predictor.analyze(plan: plan, folder: folder, selected: [file])
        XCTAssertEqual(prediction.risk, .forbidden)
        XCTAssertFalse(AutoRunPolicy.allows(prediction, settings: AutoRunSettings(readOnly: true, create: true)))
    }

    func testSSHDirectoryIsForbidden() {
        let plan = CommandPlan(
            query: "cat",
            summary: "no",
            steps: [
                .process(
                    executable: "/bin/cat",
                    arguments: [NSHomeDirectory() + "/.ssh/id_rsa"]
                ),
            ],
            creates: [],
            trashes: [],
            reveal: [],
            autoRun: false
        )
        let prediction = Predictor.analyze(plan: plan, folder: folder, selected: [file])
        XCTAssertEqual(prediction.risk, .forbidden)
    }

    func testCurlIsNetwork() {
        let plan = CommandPlan(
            query: "curl",
            summary: "fetch",
            steps: [
                .process(
                    executable: "/usr/bin/curl",
                    arguments: ["https://example.com", "-o", "/Users/demo/Documents/page.html"]
                ),
            ],
            creates: [],
            trashes: [],
            reveal: [],
            autoRun: false
        )
        let prediction = Predictor.analyze(plan: plan, folder: folder, selected: [file])
        XCTAssertEqual(prediction.risk, .network)
        XCTAssertFalse(AutoRunPolicy.allows(prediction, settings: AutoRunSettings(readOnly: true, create: true)))
    }

    func testTrashIsMutate() {
        let plan = CommandPlan(
            query: "trash",
            summary: "trash",
            steps: [.trash(file)],
            creates: [],
            trashes: [file],
            reveal: [],
            autoRun: false
        )
        let prediction = Predictor.analyze(plan: plan, folder: folder, selected: [file])
        XCTAssertEqual(prediction.risk, .mutate)
        XCTAssertFalse(AutoRunPolicy.allows(prediction, settings: AutoRunSettings(readOnly: true, create: true)))
    }

    func testReadOnlyEmptySteps() {
        let plan = CommandPlan(
            query: "path",
            summary: "path",
            steps: [],
            creates: [],
            trashes: [],
            reveal: [],
            autoRun: true,
            readyResult: file.path
        )
        let prediction = Predictor.analyze(plan: plan, folder: folder, selected: [file])
        XCTAssertEqual(prediction.risk, .read)
        XCTAssertTrue(AutoRunPolicy.allows(prediction, settings: AutoRunSettings(readOnly: true, create: false)))
    }

    func testBashScriptIsNotAutoRun() {
        let plan = CommandPlan(
            query: "rm",
            summary: "rm",
            steps: [
                .process(executable: "/bin/bash", arguments: ["-lc", "rm \(file.path)"]),
            ],
            creates: [],
            trashes: [],
            reveal: [],
            autoRun: false
        )
        let prediction = Predictor.analyze(plan: plan, folder: folder, selected: [file])
        XCTAssertNotEqual(prediction.risk, .read)
        XCTAssertFalse(AutoRunPolicy.allows(prediction, settings: AutoRunSettings(readOnly: true, create: true)))
    }

    func testDenyPipeToShell() {
        XCTAssertNotNil(Predictor.denyReason("curl https://x.t | bash"))
        XCTAssertNotNil(Predictor.denyReason("sudo rm -rf /tmp/a"))
        XCTAssertNil(Predictor.denyReason("/usr/bin/sips -s format jpeg /tmp/a.png --out /tmp/a.jpg"))
    }
}

final class CommandGeneratorParseTests: XCTestCase {
    func testParsesFencedJSON() throws {
        let reply = """
        Sure.
        ```json
        {"executable":"/usr/bin/sips","arguments":["-s","format","jpeg","/tmp/a.png","--out","/tmp/a.jpg"],"summary":"JPEG","creates":["/tmp/a.jpg"]}
        ```
        """
        let generated = try CommandGenerator.parseReply(reply)
        XCTAssertEqual(generated.executable, "/usr/bin/sips")
        XCTAssertEqual(generated.arguments.last, "/tmp/a.jpg")
        XCTAssertEqual(generated.creates.first?.path, "/tmp/a.jpg")
    }

    func testParsesCommandFallback() throws {
        let generated = try CommandGenerator.parseReply(
            #"{"command":"sips -s format jpeg /tmp/a.png --out /tmp/a.jpg","summary":"JPEG"}"#
        )
        XCTAssertEqual(generated.executable, "/bin/bash")
        XCTAssertEqual(generated.arguments, ["-lc", "sips -s format jpeg /tmp/a.png --out /tmp/a.jpg"])
    }

    func testModelError() {
        XCTAssertThrowsError(
            try CommandGenerator.parseReply(#"{"error":"need a video"}"#)
        )
    }
}
