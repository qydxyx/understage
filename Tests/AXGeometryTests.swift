import XCTest
@testable import Understage

final class AXGeometryTests: XCTestCase {
    func testCocoaRectFlipsYFromTopLeftOrigin() {
        let rect = AXGeometry.cocoaRect(
            axPosition: CGPoint(x: 100, y: 22),
            axSize: CGSize(width: 800, height: 600),
            primaryHeight: 900
        )
        XCTAssertEqual(rect.origin.x, 100)
        XCTAssertEqual(rect.origin.y, 278)
        XCTAssertEqual(rect.size.width, 800)
        XCTAssertEqual(rect.size.height, 600)
    }

    func testBarSitsBelowWindowWhenThereIsRoom() {
        let window = CGRect(x: 40, y: 200, width: 900, height: 500)
        let visible = CGRect(x: 0, y: 40, width: 1440, height: 860)
        let frame = BarPlacement.frame(window: window, visible: visible, height: 52, overlap: 1)
        XCTAssertEqual(frame.minY, 149)
        XCTAssertEqual(frame.width, 900)
        XCTAssertEqual(frame.height, 52)
    }

    func testCGWindowBoundsDictionaryParses() {
        let rect = CGWindowFrames.rect(from: ["X": 100, "Y": 22, "Width": 800, "Height": 600])
        XCTAssertEqual(rect, CGRect(x: 100, y: 22, width: 800, height: 600))
    }

    func testContextIgnoresFrameForContentEquality() {
        let a = StageContext(
            windowID: 1,
            folderURL: URL(fileURLWithPath: "/tmp"),
            folderName: "tmp",
            selected: [],
            title: "tmp",
            cocoaFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            isDesktop: false
        )
        var b = a
        b.cocoaFrame.origin.x = 50
        XCTAssertTrue(a.sameContent(as: b))
        b.title = "other"
        XCTAssertFalse(a.sameContent(as: b))
    }

    func testBarOverlaysWindowWhenBelowWouldClip() {
        let window = CGRect(x: 40, y: 40, width: 900, height: 700)
        let visible = CGRect(x: 0, y: 40, width: 1440, height: 860)
        let frame = BarPlacement.frame(window: window, visible: visible, height: 52, overlap: 1)
        XCTAssertEqual(frame.minY, 44)
    }
}

final class FinderScriptingMatchTests: XCTestCase {
    func testMatchPrefersSameTitleThenClosestSize() {
        let windows = [
            ScriptingFinderWindow(
                id: 1,
                name: "Downloads",
                width: 800,
                height: 600,
                target: URL(fileURLWithPath: "/Users/a/Downloads")
            ),
            ScriptingFinderWindow(
                id: 2,
                name: "Downloads",
                width: 1200,
                height: 800,
                target: URL(fileURLWithPath: "/Users/a/Downloads/archive")
            ),
        ]
        let url = FinderScripting.matchTarget(
            title: "Downloads",
            cocoaSize: CGSize(width: 1190, height: 790),
            windows: windows
        )
        XCTAssertEqual(url?.path, "/Users/a/Downloads/archive")
    }
}
