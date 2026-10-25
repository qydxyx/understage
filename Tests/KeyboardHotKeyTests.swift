import Carbon
import XCTest
@testable import Understage

@MainActor
final class KeyboardHotKeyTests: XCTestCase {
    func testHotKeyOptionDefinitions() {
        XCTAssertEqual(HotKeyOption.optionSpace.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(HotKeyOption.optionSpace.modifiers, UInt32(optionKey))

        XCTAssertEqual(HotKeyOption.optionCommandU.keyCode, UInt32(kVK_ANSI_U))
        XCTAssertEqual(HotKeyOption.optionCommandU.modifiers, UInt32(optionKey | cmdKey))

        XCTAssertEqual(HotKeyOption.controlSpace.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(HotKeyOption.controlSpace.modifiers, UInt32(controlKey))

        XCTAssertNil(HotKeyOption.disabled.keyCode)
        XCTAssertNil(HotKeyOption.disabled.modifiers)
    }

    func testHistoryNavigationAndEscape() {
        let history = TaskHistory.shared
        history.record(query: "first query", summary: "First", ok: true)
        history.record(query: "second query", summary: "Second", ok: true)

        let model = StageBarModel()
        model.query = "draft in progress"

        // Navigate up -> should show latest history ("second query")
        model.navigateHistoryUp()
        XCTAssertEqual(model.query, "second query")

        // Navigate up again -> should show earlier history ("first query")
        model.navigateHistoryUp()
        XCTAssertEqual(model.query, "first query")

        // Navigate down -> should show "second query"
        model.navigateHistoryDown()
        XCTAssertEqual(model.query, "second query")

        // Navigate down again -> should restore stashed "draft in progress"
        model.navigateHistoryDown()
        XCTAssertEqual(model.query, "draft in progress")

        // Test Escape with text -> should clear text
        model.handleEscape()
        XCTAssertEqual(model.query, "")

        // Test Escape in thinking or result phase
        model.phase = .result(ok: true, text: "Done")
        model.handleEscape()
        XCTAssertEqual(model.phase, .idle)
    }
}
