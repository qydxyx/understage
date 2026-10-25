import AppKit
import CoreGraphics

enum AXGeometry {
    /// Accessibility position is top-left, origin at the top-left of the primary display.
    /// Cocoa frames are bottom-left, with the primary display origin at (0, 0).
    static func cocoaRect(axPosition: CGPoint, axSize: CGSize) -> CGRect {
        cocoaRect(axPosition: axPosition, axSize: axSize, primaryHeight: primaryScreenHeight())
    }

    static func cocoaRect(axPosition: CGPoint, axSize: CGSize, primaryHeight: CGFloat) -> CGRect {
        let y = primaryHeight - axPosition.y - axSize.height
        return CGRect(x: axPosition.x, y: y, width: axSize.width, height: axSize.height)
    }

    static func screen(containing rect: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        if let hit = screens.first(where: { $0.frame.intersects(rect) }) {
            return hit
        }
        return screens.max(by: { intersectionArea($0.frame, rect) < intersectionArea($1.frame, rect) })
            ?? NSScreen.main
    }

    static func primaryScreenHeight() -> CGFloat {
        if let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) {
            return primary.frame.height
        }
        return NSScreen.main?.frame.height ?? 0
    }

    private static func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }
}

enum BarPlacement {
    static let height: CGFloat = 52
    static let overlap: CGFloat = 1

    /// Sit flush under the Finder window. If that would leave the visible
    /// screen, overlay the window's bottom edge instead.
    static func frame(forWindow window: CGRect, on screen: NSScreen, height: CGFloat = height) -> CGRect {
        frame(window: window, visible: screen.visibleFrame, height: height, overlap: overlap)
    }

    static func frame(window: CGRect, visible: CGRect, height: CGFloat, overlap: CGFloat) -> CGRect {
        let width = max(320, window.width)
        let x = window.minX
        let below = CGRect(
            x: x,
            y: window.minY - height + overlap,
            width: width,
            height: height
        )
        if below.minY >= visible.minY {
            return below
        }
        return CGRect(
            x: x,
            y: window.minY + 4,
            width: width,
            height: height
        )
    }

    static func desktopBarFrame(on screen: NSScreen, height: CGFloat = height) -> CGRect {
        let visible = screen.visibleFrame
        return CGRect(
            x: visible.minX + 16,
            y: visible.minY + 8,
            width: max(480, visible.width - 32),
            height: height
        )
    }
}
