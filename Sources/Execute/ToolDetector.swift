import Foundation

struct Toolset: Equatable, Sendable {
    var ffmpeg: String?
    var sips: String?
    var afconvert: String?
    var textutil: String?
    var zip: String?
    var ditto: String?

    static var system: Toolset { ToolDetector.detect() }
}

enum ToolDetector {
    static let searchRoots = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
    ]

    static func detect() -> Toolset {
        Toolset(
            ffmpeg: which("ffmpeg"),
            sips: which("sips"),
            afconvert: which("afconvert"),
            textutil: which("textutil"),
            zip: which("zip"),
            ditto: which("ditto")
        )
    }

    static func which(_ name: String) -> String? {
        for root in searchRoots {
            let path = "\(root)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}
