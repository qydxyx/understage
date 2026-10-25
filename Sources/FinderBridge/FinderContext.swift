import Foundation

struct SelectedItem: Identifiable, Equatable, Sendable {
    var url: URL
    var name: String
    var isDirectory: Bool

    var id: URL { url }
}

struct StageContext: Equatable, Sendable {
    var windowID: UInt32
    var folderURL: URL?
    var folderName: String
    var selected: [SelectedItem]
    var title: String
    var cocoaFrame: CGRect
    var isDesktop: Bool

    func sameContent(as other: StageContext) -> Bool {
        windowID == other.windowID
            && folderURL == other.folderURL
            && folderName == other.folderName
            && selected == other.selected
            && title == other.title
            && isDesktop == other.isDesktop
    }
}

enum WindowKey: Hashable {
    case cgWindow(UInt32)
    case desktop
    case fallback(String)
}
