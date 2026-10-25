import Foundation

enum OutputFormat: String, Equatable, Sendable {
    case jpg, png, webp, heic, mp4, mp3, wav, gif, pdf, txt, docx

    var pathExtension: String {
        switch self {
        case .jpg: "jpg"
        case .png: "png"
        case .webp: "webp"
        case .heic: "heic"
        case .mp4: "mp4"
        case .mp3: "mp3"
        case .wav: "wav"
        case .gif: "gif"
        case .pdf: "pdf"
        case .txt: "txt"
        case .docx: "docx"
        }
    }
}

enum InfoField: String, Equatable, Sendable {
    case size, resolution, codec, fps, duration, wordCount, lineCount, path, fileType
}

enum InstantAction: Equatable, Sendable {
    case convert(OutputFormat)
    case scaleVideo(height: Int)
    case extractAudio
    case stripAudio
    case info(InfoField)
    case zip
    case unzip
    case duplicate
    case trash
    case openTerminal
    case copyPath
    case selectAll(ext: String)
    case selectLast(ext: String)
}

enum InstantParser {
    static func parse(_ raw: String) -> InstantAction? {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return nil }
        if let select = parseSelect(lower) { return select }

        let compact = stripFiller(lower)

        if compact.contains("1080") { return .scaleVideo(height: 1080) }
        if compact.contains("720") { return .scaleVideo(height: 720) }
        if matches(compact, ["extract audio", "提取音频", "抽音频", "音频提取"]) {
            return .extractAudio
        }
        if matches(compact, ["strip audio", "remove audio", "去音频", "去掉音频", "无音频"]) {
            return .stripAudio
        }
        if matches(compact, ["word count", "词数", "字数", "字数统计"]) { return .info(.wordCount) }
        if matches(compact, ["lines of code", "line count", "行数", "多少行"]) { return .info(.lineCount) }
        if matches(compact, ["file size", "size", "大小"]) { return .info(.size) }
        if matches(compact, ["resolution", "分辨率"]) { return .info(.resolution) }
        if matches(compact, ["codec", "编码"]) { return .info(.codec) }
        if matches(compact, ["fps", "帧率"]) { return .info(.fps) }
        if matches(compact, ["duration", "时长", "长度"]) { return .info(.duration) }
        if matches(compact, ["copy path", "复制路径"]) { return .copyPath }
        if matches(compact, ["path", "路径"]) { return .info(.path) }
        if matches(compact, ["type", "kind", "类型"]) { return .info(.fileType) }
        if matches(compact, ["open terminal", "terminal", "term", "打开终端", "终端"]) {
            return .openTerminal
        }
        if matches(compact, ["unzip", "解压", "解压缩"]) { return .unzip }
        if matches(compact, ["zip", "压缩", "打包"]) { return .zip }
        if matches(compact, ["duplicate", "副本", "复制一份", "拷贝一份"]) { return .duplicate }
        if matches(compact, ["trash", "废纸篓", "丢进废纸篓", "删掉", "删除"]) { return .trash }

        let formats: [(OutputFormat, [String])] = [
            (.jpg, ["jpg", "jpeg", "转jpg"]),
            (.png, ["png", "转png"]),
            (.webp, ["webp", "转webp"]),
            (.heic, ["heic", "转heic"]),
            (.mp4, ["mp4", "转mp4"]),
            (.mp3, ["mp3", "转mp3"]),
            (.wav, ["wav", "转wav"]),
            (.gif, ["gif", "animated gif", "转gif"]),
            (.pdf, ["pdf", "转pdf"]),
            (.txt, ["txt", "plain text", "纯文本"]),
            (.docx, ["docx", "word", "word doc", "文档"]),
        ]
        for (format, aliases) in formats {
            if matches(compact, aliases) { return .convert(format) }
        }
        return nil
    }

    static func normalizeExtension(_ token: String) -> String {
        var t = token.lowercased()
        if t.hasPrefix(".") { t.removeFirst() }
        if t.hasSuffix("s"), t.count > 2 { t.removeLast() }
        switch t {
        case "jpeg": return "jpg"
        case "plain text", "text": return "txt"
        case "word", "word doc", "doc": return "docx"
        default: return t
        }
    }

    private static func parseSelect(_ lower: String) -> InstantAction? {
        let allPrefixes = ["select all ", "选中所有", "全选"]
        let lastPrefixes = ["select last ", "选中最后一个", "选中最后"]
        for prefix in allPrefixes {
            if lower.hasPrefix(prefix) {
                let rest = String(lower.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { return .selectAll(ext: normalizeExtension(rest)) }
            }
        }
        for prefix in lastPrefixes {
            if lower.hasPrefix(prefix) {
                let rest = String(lower.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { return .selectLast(ext: normalizeExtension(rest)) }
            }
        }
        return nil
    }

    private static func stripFiller(_ value: String) -> String {
        var s = value
        let fillers = [
            "convert to ", "convert ", "make an ", "make a ", "make ",
            "please ", " please",
            "帮我", "请把", "请", "转成", "转换为", "转换成", "转为", "一下",
        ]
        var changed = true
        while changed {
            changed = false
            for filler in fillers {
                if s.hasPrefix(filler) {
                    s = String(s.dropFirst(filler.count))
                    changed = true
                }
                if s.hasSuffix(filler) {
                    s = String(s.dropLast(filler.count))
                    changed = true
                }
            }
        }
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func matches(_ compact: String, _ aliases: [String]) -> Bool {
        aliases.contains { compact == $0 || compact.hasPrefix($0 + " ") || compact.hasSuffix(" " + $0) }
    }
}
