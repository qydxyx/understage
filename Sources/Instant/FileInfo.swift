import AVFoundation
import CoreMedia
import Foundation
import ImageIO

enum FileInfo {
    static func report(field: InfoField, items: [SelectedItem], folder: URL?) -> String {
        let urls: [URL]
        if items.isEmpty, let folder {
            urls = [folder]
        } else {
            urls = items.map(\.url)
        }
        guard !urls.isEmpty else { return "Nothing selected." }
        return urls.map { line(field, $0) }.joined(separator: "\n")
    }

    private static func line(_ field: InfoField, _ url: URL) -> String {
        let name = url.lastPathComponent
        switch field {
        case .path:
            return "\(name): \(url.path)"
        case .size:
            return "\(name): \(sizeString(url))"
        case .fileType:
            return "\(name): \(url.pathExtension.uppercased().nilIfEmpty ?? "folder/unknown")"
        case .wordCount:
            return "\(name): \(wordCount(url))"
        case .charCount:
            return "\(name): \(characterCount(url))"
        case .lineCount:
            return "\(name): \(lineCount(url))"
        case .resolution:
            return "\(name): \(resolution(url))"
        case .duration:
            return "\(name): \(duration(url))"
        case .codec:
            return "\(name): \(codec(url))"
        case .fps:
            return "\(name): \(fps(url))"
        }
    }

    private static func sizeString(_ url: URL) -> String {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]) else {
            return "unknown"
        }
        if values.isDirectory == true { return "folder" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(values.fileSize ?? 0))
    }

    private static func wordCount(_ url: URL) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "not text" }
        let words = text.split { $0.isWhitespace || $0.isNewline }
        return "\(words.count) words"
    }

    private static func characterCount(_ url: URL) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "not text" }
        let count = text.filter { !$0.isWhitespace }.count
        return "\(count) chars"
    }

    static func reportLoaded(field: InfoField, items: [SelectedItem], folder: URL?) async -> String {
        switch field {
        case .duration, .codec, .fps:
            return await mediaReport(field, items: items, folder: folder)
        default:
            return report(field: field, items: items, folder: folder)
        }
    }

    private static func mediaReport(_ field: InfoField, items: [SelectedItem], folder: URL?) async -> String {
        let urls: [URL]
        if items.isEmpty, let folder {
            urls = [folder]
        } else {
            urls = items.map(\.url)
        }
        guard !urls.isEmpty else { return "Nothing selected." }
        var lines: [String] = []
        for url in urls {
            lines.append(await mediaLine(field, url))
        }
        return lines.joined(separator: "\n")
    }

    private static func mediaLine(_ field: InfoField, _ url: URL) async -> String {
        let name = url.lastPathComponent
        let asset = AVURLAsset(url: url)
        switch field {
        case .duration:
            let duration = (try? await asset.load(.duration)) ?? .indefinite
            let seconds = CMTimeGetSeconds(duration)
            guard seconds.isFinite, seconds > 0 else { return "\(name): unknown" }
            if seconds < 60 { return "\(name): \(String(format: "%.1fs", seconds))" }
            let m = Int(seconds) / 60
            let s = Int(seconds) % 60
            return "\(name): \(m)m \(s)s"
        case .codec:
            let tracks = (try? await asset.load(.tracks)) ?? []
            var names: [String] = []
            for track in tracks {
                let descriptions = (try? await track.load(.formatDescriptions)) ?? []
                guard let desc = descriptions.first else { continue }
                names.append(fourCC(CMFormatDescriptionGetMediaSubType(desc)))
            }
            return names.isEmpty ? "\(name): unknown" : "\(name): \(names.joined(separator: ", "))"
        case .fps:
            let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            guard let track = tracks.first else { return "\(name): n/a" }
            let rate = (try? await track.load(.nominalFrameRate)) ?? 0
            return rate > 0 ? "\(name): \(String(format: "%.2f fps", rate))" : "\(name): unknown"
        default:
            return "\(name): unknown"
        }
    }

    private static func lineCount(_ url: URL) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "not text" }
        return "\(text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count) lines"
    }

    private static func resolution(_ url: URL) -> String {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? NSNumber,
           let h = props[kCGImagePropertyPixelHeight] as? NSNumber
        {
            return "\(w.intValue)×\(h.intValue)"
        }
        let asset = AVURLAsset(url: url)
        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize
            return "\(Int(size.width))×\(Int(size.height))"
        }
        return "unknown"
    }

    private static func duration(_ url: URL) -> String {
        let seconds = CMTimeGetSeconds(AVURLAsset(url: url).duration)
        guard seconds.isFinite, seconds > 0 else { return "unknown" }
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return "\(m)m \(s)s"
    }

    private static func codec(_ url: URL) -> String {
        let asset = AVURLAsset(url: url)
        let names = asset.tracks.compactMap { track -> String? in
            guard let desc = track.formatDescriptions.first else { return nil }
            let format = desc as! CMFormatDescription
            return fourCC(CMFormatDescriptionGetMediaSubType(format))
        }
        return names.isEmpty ? "unknown" : names.joined(separator: ", ")
    }

    private static func fps(_ url: URL) -> String {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return "n/a" }
        let rate = track.nominalFrameRate
        return rate > 0 ? String(format: "%.2f fps", rate) : "unknown"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private func fourCC(_ code: FourCharCode) -> String {
    let chars = [
        UInt8((code >> 24) & 0xFF),
        UInt8((code >> 16) & 0xFF),
        UInt8((code >> 8) & 0xFF),
        UInt8(code & 0xFF),
    ]
    return String(bytes: chars, encoding: .ascii) ?? "\(code)"
}
