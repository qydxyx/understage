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
    case size, resolution, codec, fps, duration, wordCount, charCount, lineCount, path, fileType
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
    case mergePDF
    case splitPDF
    case ocr
    case renameNumbered
    case renameDatePrefix
    case renameCase(lowercase: Bool)
    case renamePrefix(String)
    case renameSuffix(String)
    case renameReplace(target: String, replacement: String)
    case organizeByType
    case encodeHEVC(height: Int?)
}

enum InstantParser {
    static func parse(_ raw: String) -> InstantAction? {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return nil }
        if let select = parseSelect(lower) { return select }

        let compact = stripFiller(lower)

        if organizeByTypePhrase(compact) { return .organizeByType }
        if let hevc = parseHEVC(compact) { return hevc }
        if compact == "1080" || compact == "1080p" { return .scaleVideo(height: 1080) }
        if compact == "720" || compact == "720p" { return .scaleVideo(height: 720) }
        if matches(compact, ["extract audio", "提取音频", "抽音频", "音频提取"]) {
            return .extractAudio
        }
        if matches(compact, ["strip audio", "remove audio", "去音频", "去掉音频", "无音频"]) {
            return .stripAudio
        }
        if matches(compact, ["字数", "字数统计", "character count"]) { return .info(.charCount) }
        if matches(compact, ["word count", "词数"]) { return .info(.wordCount) }
        if matches(compact, ["lines of code", "line count", "行数", "多少行"]) { return .info(.lineCount) }
        if matches(compact, ["file size"]) || matchesExact(compact, ["size", "大小"]) { return .info(.size) }
        if matches(compact, ["resolution", "分辨率"]) { return .info(.resolution) }
        if matches(compact, ["编码"]) || matchesExact(compact, ["codec"]) { return .info(.codec) }
        if matches(compact, ["帧率"]) || matchesExact(compact, ["fps"]) { return .info(.fps) }
        if matches(compact, ["时长", "长度"]) || matchesExact(compact, ["duration"]) { return .info(.duration) }
        if matches(compact, ["copy path", "复制路径"]) { return .copyPath }
        if matchesExact(compact, ["path", "路径"]) { return .info(.path) }
        if matchesExact(compact, ["type", "kind", "类型"]) { return .info(.fileType) }
        if matches(compact, ["open terminal", "terminal", "term", "打开终端", "终端"]) {
            return .openTerminal
        }
        if matches(compact, ["unzip", "解压", "解压缩"]) { return .unzip }
        if matches(compact, ["zip", "压缩", "打包"]) { return .zip }
        if matches(compact, ["duplicate", "副本", "复制一份", "拷贝一份"]) { return .duplicate }
        if matches(compact, ["trash", "废纸篓", "丢进废纸篓", "删掉", "删除"]) { return .trash }

        // PDF Operations
        if matches(compact, ["merge pdf", "pdf merge", "combine pdf", "合并 pdf", "合并为 pdf", "合并为pdf", "合并pdf", "拼合 pdf", "组合 pdf"]) {
            return .mergePDF
        }
        if matches(compact, ["split pdf", "pdf split", "拆分 pdf", "拆分pdf", "按页拆分", "拆分每页"]) {
            return .splitPDF
        }

        // OCR
        if matches(compact, ["ocr", "提取文字", "文字提取", "识别文字", "文字识别", "extract text", "recognize text"]) {
            return .ocr
        }

        // Batch Rename
        if let rename = parseRename(compact: compact, lower: lower) {
            return rename
        }

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

    /// `hevc 720p` and `h265` are transcodes. A bare `720p` stays a scale.
    private static func parseHEVC(_ compact: String) -> InstantAction? {
        let hevc = compact.contains("hevc") || compact.contains("h265") || compact.contains("h.265")
        guard hevc else { return nil }
        if compact.contains("1080") { return .encodeHEVC(height: 1080) }
        if compact.contains("720") { return .encodeHEVC(height: 720) }
        return .encodeHEVC(height: nil)
    }

    private static func organizeByTypePhrase(_ compact: String) -> Bool {
        let phrases = [
            "by type", "by file type", "according to type", "according to their type",
            "按类型", "按文件类型", "根据类型", "根据文件类型", "按扩展名", "分门别类",
            "不同类型", "不同的文件夹", "different folders", "整理文件", "整理一下", "分类整理",
        ]
        if phrases.contains(where: { compact.contains($0) }) { return true }
        // Bare imperatives ("整理", "分类", "organize") are the common way to ask
        // this with a multi-file selection, and they must not need a model.
        var head = compact
        for tail in ["一下这些文件", "这些文件", "所选文件", "一下文件", "文件", "文件夹",
                     "these files", "the files", "selected files", "files", "file",
                     "这些", "所选", "一下", "吧"] {
            if head.hasSuffix(tail) { head = String(head.dropLast(tail.count)) }
        }
        let verbs = ["整理", "分类", "归类", "归档", "organize", "organise", "tidy", "sort"]
        return verbs.contains(head.trimmingCharacters(in: .whitespaces))
    }

    /// Single common words only match the whole command. A sentence that merely ends in "type" is not a file-type lookup.
    private static func matchesExact(_ compact: String, _ aliases: [String]) -> Bool {
        aliases.contains { compact == $0 }
    }

    private static func parseRename(compact: String, lower: String) -> InstantAction? {
        if matches(compact, ["1 2 3", "123", "number", "numbering", "number files", "序号", "按序号", "序号重命名", "重命名 1 2 3", "按序号命名", "加序号"]) {
            return .renameNumbered
        }
        if matches(compact, ["date prefix", "add date", "add date prefix", "加日期", "日期前缀", "按日期重命名", "添加日期前缀", "加时间戳", "加日期前缀"]) {
            return .renameDatePrefix
        }
        if matches(compact, ["lowercase", "to lowercase", "转小写", "全小写", "改成小写", "全部小写"]) {
            return .renameCase(lowercase: true)
        }
        if matches(compact, ["uppercase", "to uppercase", "转大写", "全大写", "改成大写", "全部大写"]) {
            return .renameCase(lowercase: false)
        }

        // Prefix: "prefix foo", "add prefix foo", "加前缀 foo", "前缀 foo"
        let prefixKeys = ["add prefix ", "prefix ", "加前缀 ", "添加前缀 ", "前缀 "]
        for key in prefixKeys {
            if lower.hasPrefix(key) {
                let val = String(lower.dropFirst(key.count)).trimmingCharacters(in: .whitespaces)
                if !val.isEmpty { return .renamePrefix(val) }
            }
        }

        // Suffix: "suffix foo", "add suffix foo", "加后缀 foo", "后缀 foo"
        let suffixKeys = ["add suffix ", "suffix ", "加后缀 ", "添加后缀 ", "后缀 "]
        for key in suffixKeys {
            if lower.hasPrefix(key) {
                let val = String(lower.dropFirst(key.count)).trimmingCharacters(in: .whitespaces)
                if !val.isEmpty { return .renameSuffix(val) }
            }
        }

        // Replace: "replace foo with bar"
        if lower.hasPrefix("replace ") && lower.contains(" with ") {
            let withoutReplace = String(lower.dropFirst("replace ".count))
            let parts = withoutReplace.components(separatedBy: " with ")
            if parts.count == 2 {
                let target = parts[0].trimmingCharacters(in: .whitespaces)
                let rep = parts[1].trimmingCharacters(in: .whitespaces)
                if !target.isEmpty {
                    return .renameReplace(target: target, replacement: rep)
                }
            }
        }

        // Chinese Replace patterns
        let chinesePatterns: [(prefix: String, mid: String)] = [
            ("把 ", " 替换为 "),
            ("把 ", " 换成 "),
            ("把 ", " 替换成 "),
            ("把 ", " 改为 "),
            ("将 ", " 替换为 "),
            ("将 ", " 换成 "),
            ("将 ", " 替换成 "),
            ("替换 ", " 为 "),
            ("替换 ", " 成 "),
        ]
        for pat in chinesePatterns {
            if lower.hasPrefix(pat.prefix) && lower.contains(pat.mid) {
                let withoutPrefix = String(lower.dropFirst(pat.prefix.count))
                let parts = withoutPrefix.components(separatedBy: pat.mid)
                if parts.count == 2 {
                    let target = parts[0].trimmingCharacters(in: .whitespaces)
                    let rep = parts[1].trimmingCharacters(in: .whitespaces)
                    if !target.isEmpty {
                        return .renameReplace(target: target, replacement: rep)
                    }
                }
            }
        }

        return nil
    }
}
