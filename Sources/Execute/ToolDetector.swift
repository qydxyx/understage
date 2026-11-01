import Foundation
import UniformTypeIdentifiers

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

    /// GUI launches do not inherit a shell PATH. A bare `ffmpeg` is not a file.
    static func resolve(_ executable: String) -> String {
        if executable.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executable) {
            return executable
        }
        let name = URL(fileURLWithPath: executable).lastPathComponent
        return which(name) ?? executable
    }
}

enum FileCategory {
    static let images = "图片"
    static let documents = "文档"
    static let videos = "视频"
    static let audio = "音频"
    static let archives = "压缩包"
    static let other = "其他"

    static func folder(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: ext)
        if let type {
            if type.conforms(to: .image) { return images }
            if type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .quickTimeMovie) {
                return videos
            }
            if type.conforms(to: .audio) { return audio }
            if type.conforms(to: .pdf) { return documents }
        }
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp", "raw", "svg", "ico", "avif":
            return images
        case "mp4", "mov", "m4v", "mkv", "avi", "webm", "flv", "wmv":
            return videos
        case "mp3", "wav", "m4a", "aac", "aiff", "caf", "flac":
            return audio
        case "pdf", "doc", "docx", "dot", "dotx", "xls", "xlsx", "xlsm", "ppt", "pptx", "pps", "ppsx",
             "pages", "numbers", "key", "odt", "ods", "odp", "rtf", "csv", "epub":
            return documents
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "dmg":
            return archives
        default:
            return other
        }
    }
}
