import ApplicationServices
import AppKit
import Darwin

struct AXFinderWindow {
    var key: WindowKey
    var element: AXUIElement
    var cocoaFrame: CGRect
    var title: String
    var documentURL: URL?
    var selected: [SelectedItem]
    var isMinimized: Bool
}

enum FinderAX {
    static let finderBundleID = "com.apple.finder"

    static var finderPID: pid_t? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == finderBundleID }?
            .processIdentifier
    }

    static func applicationElement() -> AXUIElement? {
        guard let pid = finderPID else { return nil }
        return AXUIElementCreateApplication(pid)
    }

    static func windows() -> [AXFinderWindow] {
        guard let app = applicationElement() else { return [] }
        let elements: [AXUIElement] = AXAttr.copy(app, "AXWindows") ?? []
        return elements.compactMap(describe)
    }

    static func isFinderFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == finderBundleID
    }

    static func activateFinder() {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == finderBundleID }) {
            app.activate()
        }
    }

    static func focusedWindow() -> AXFinderWindow? {
        guard let app = applicationElement() else { return nil }
        if let focused: AXUIElement = AXAttr.copy(app, "AXFocusedWindow"),
           let described = describe(focused), !described.isMinimized {
            return described
        }
        if let main: AXUIElement = AXAttr.copy(app, "AXMainWindow"),
           let described = describe(main), !described.isMinimized {
            return described
        }
        return windows().first { !$0.isMinimized }
    }

    private static func describe(_ element: AXUIElement) -> AXFinderWindow? {
        let role: String? = AXAttr.copy(element, "AXRole")
        if let role, role != "AXWindow" { return nil }
        let minimized = AXAttr.bool(element, "AXMinimized") ?? false
        guard let position = AXAttr.point(element, "AXPosition"),
              let size = AXAttr.size(element, "AXSize")
        else { return nil }
        let frame = AXGeometry.cocoaRect(axPosition: position, axSize: size)
        guard frame.width > 80, frame.height > 80 else { return nil }
        let title: String = AXAttr.copy(element, "AXTitle") ?? ""
        let document = AXAttr.fileURL(element, "AXDocument")
        let selected = selectedItems(in: element)
        let key: WindowKey
        if let id = PrivateAX.windowID(of: element), id != 0 {
            key = .cgWindow(id)
        } else {
            key = .fallback(
                "\(title)-\(Int(frame.origin.x))-\(Int(frame.origin.y))-\(Int(frame.width))-\(Int(frame.height))"
            )
        }
        return AXFinderWindow(
            key: key,
            element: element,
            cocoaFrame: frame,
            title: title,
            documentURL: document,
            selected: selected,
            isMinimized: minimized
        )
    }

    private static func selectedItems(in window: AXUIElement) -> [SelectedItem] {
        var items: [SelectedItem] = []
        var seen = Set<URL>()
        collectSelected(window, depth: 0, into: &items, seen: &seen)
        return items
    }

    private static func collectSelected(
        _ element: AXUIElement,
        depth: Int,
        into items: inout [SelectedItem],
        seen: inout Set<URL>
    ) {
        if depth > 8 { return }
        let selectedLists: [[AXUIElement]] = [
            AXAttr.copy(element, "AXSelectedChildren") ?? [],
            AXAttr.copy(element, "AXSelectedRows") ?? [],
        ]
        for selected in selectedLists {
            for child in selected {
                if let item = item(from: child), seen.insert(item.url).inserted {
                    items.append(item)
                } else {
                    collectSelected(child, depth: depth + 1, into: &items, seen: &seen)
                }
            }
        }
        if items.isEmpty, depth < 4 {
            let children: [AXUIElement] = AXAttr.copy(element, "AXChildren") ?? []
            for child in children.prefix(12) {
                let role: String = AXAttr.copy(child, "AXRole") ?? ""
                if interestingRole(role) {
                    collectSelected(child, depth: depth + 1, into: &items, seen: &seen)
                }
            }
        }
    }

    private static func interestingRole(_ role: String) -> Bool {
        role == "AXScrollArea"
            || role == "AXSplitGroup"
            || role == "AXOutline"
            || role == "AXList"
            || role == "AXBrowser"
            || role == "AXGroup"
            || role == "AXRow"
            || role == "AXLayoutArea"
    }

    private static func item(from element: AXUIElement) -> SelectedItem? {
        guard let url = fileURL(from: element) else { return nil }
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let name = url.lastPathComponent
        return SelectedItem(url: url, name: name, isDirectory: isDirectory.boolValue)
    }

    private static func fileURL(from element: AXUIElement) -> URL? {
        if let url = AXAttr.fileURL(element, "AXURL") { return url }
        if let url = AXAttr.fileURL(element, "AXDocument") { return url }
        let children: [AXUIElement] = AXAttr.copy(element, "AXChildren") ?? []
        for child in children.prefix(6) {
            if let url = AXAttr.fileURL(child, "AXURL") { return url }
            if let url = AXAttr.fileURL(child, "AXDocument") { return url }
        }
        return nil
    }
}

enum AXAttr {
    static func copy<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value as? T
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        copy(element, attribute)
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = axValue(element, attribute) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = axValue(element, attribute) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    static func fileURL(_ element: AXUIElement, _ attribute: String) -> URL? {
        if let url: URL = copy(element, attribute) { return url }
        if let string: String = copy(element, attribute) {
            if let url = URL(string: string), url.isFileURL { return url }
            if string.hasPrefix("/") { return URL(fileURLWithPath: string) }
        }
        return nil
    }
}

enum PrivateAX {
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        typealias Fn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow")
        else { return nil }
        let function = unsafeBitCast(symbol, to: Fn.self)
        var identifier: CGWindowID = 0
        let error = function(element, &identifier)
        return error == .success ? identifier : nil
    }
}
