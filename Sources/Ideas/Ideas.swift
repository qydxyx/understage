import Foundation

struct Idea: Identifiable, Equatable, Sendable {
    var id: String { query + title }
    var title: String
    var query: String
}

enum Ideas {
    static func suggestions(selected: [SelectedItem], folder: URL?, favorites: [Favorite] = []) -> [Idea] {
        var ideas: [Idea] = []
        let exts = Set(selected.map { $0.url.pathExtension.lowercased() }.filter { !$0.isEmpty })
        let hasImages = !exts.isDisjoint(with: ["png", "jpg", "jpeg", "heic", "webp", "gif", "tif", "tiff"])
        let hasVideo = !exts.isDisjoint(with: ["mp4", "mov", "m4v", "mkv", "avi", "webm"])
        let hasAudio = !exts.isDisjoint(with: ["mp3", "wav", "m4a", "aac", "aiff", "caf"])
        let hasZip = exts.contains("zip")
        let hasPDF = exts.contains("pdf")
        let hasText = !exts.isDisjoint(with: ["txt", "md", "rtf", "docx"])

        if hasImages {
            ideas.append(contentsOf: [
                Idea(title: "JPEG", query: "jpg"),
                Idea(title: "PNG", query: "png"),
                Idea(title: "OCR", query: "ocr"),
                Idea(title: "Zip", query: "zip"),
                Idea(title: "Resolution", query: "resolution"),
            ])
        }
        if hasVideo {
            ideas.append(contentsOf: [
                Idea(title: "1080p", query: "1080p"),
                Idea(title: "Extract audio", query: "extract audio"),
                Idea(title: "GIF", query: "gif"),
            ])
        }
        if hasAudio {
            ideas.append(Idea(title: "WAV", query: "wav"))
        }
        if hasZip {
            ideas.append(Idea(title: "Unzip", query: "unzip"))
        }
        if hasPDF {
            ideas.append(contentsOf: [
                Idea(title: "Split PDF", query: "split pdf"),
                Idea(title: "OCR", query: "ocr"),
                Idea(title: "Select all PDFs", query: "select all pdf"),
            ])
        }
        if selected.count > 1 && (hasPDF || hasImages) {
            ideas.append(Idea(title: "Merge to PDF", query: "merge pdf"))
        }
        if hasText {
            ideas.append(Idea(title: "Word count", query: "word count"))
        }
        if selected.count > 1 {
            ideas.append(contentsOf: [
                Idea(title: "Number 1 2 3", query: "1 2 3"),
                Idea(title: "Date prefix", query: "date prefix"),
                Idea(title: "Zip selection", query: "zip"),
            ])
        }
        if folder != nil {
            ideas.append(contentsOf: [
                Idea(title: "Copy path", query: "copy path"),
                Idea(title: "Terminal", query: "term"),
            ])
        }
        if !selected.isEmpty {
            ideas.append(Idea(title: "Duplicate", query: "duplicate"))
        }
        for favorite in favorites.prefix(5) {
            if !ideas.contains(where: { $0.query == favorite.query }) {
                ideas.append(Idea(title: favorite.query, query: favorite.query))
            }
        }
        var seen = Set<String>()
        return ideas.filter { seen.insert($0.query).inserted }
    }
}
