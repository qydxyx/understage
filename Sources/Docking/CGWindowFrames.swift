import CoreGraphics
import Foundation

enum CGWindowFrames {
    static func onScreen(ownerPID: pid_t) -> [CGWindowID: CGRect] {
        guard let infos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [:] }

        var frames: [CGWindowID: CGRect] = [:]
        frames.reserveCapacity(8)
        for info in infos {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == ownerPID else { continue }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }
            guard let number = info[kCGWindowNumber as String] as? NSNumber else { continue }
            let identifier = CGWindowID(truncating: number)
            guard identifier != 0, let bounds = rect(from: info[kCGWindowBounds as String]) else { continue }
            if bounds.width < 80 || bounds.height < 80 { continue }
            frames[identifier] = bounds
        }
        return frames
    }

    static func rect(from raw: Any?) -> CGRect? {
        guard let dict = raw as? [String: Any] else { return nil }
        guard let x = number(dict["X"]),
              let y = number(dict["Y"]),
              let width = number(dict["Width"]),
              let height = number(dict["Height"])
        else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func number(_ value: Any?) -> CGFloat? {
        (value as? NSNumber).map { CGFloat(truncating: $0) }
    }
}
