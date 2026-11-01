import AppKit
import SwiftUI

@MainActor
final class StageBarPanel: NSPanel {
    let model: StageBarModel
    private let hosting: NSHostingView<StageBarView>

    init(model: StageBarModel) {
        self.model = model
        hosting = NSHostingView(
            rootView: StageBarView(model: model, onFieldFocused: {})
        )
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: BarPlacement.height),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        hosting.rootView = StageBarView(model: model, onFieldFocused: { [weak self] in
            self?.focusForTyping()
        })
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        model.handleEscape()
    }

    var isComposing: Bool {
        guard let editor = fieldEditor(false, for: nil) as? NSTextInputClient else { return false }
        return editor.hasMarkedText()
    }

    func place(frame: CGRect) {
        if isComposing { return }
        let current = self.frame
        let sameSize = abs(current.width - frame.width) < 1 && abs(current.height - frame.height) < 1
        let sameOrigin = abs(current.minX - frame.minX) < 1 && abs(current.minY - frame.minY) < 1
        if sameSize && sameOrigin {
            if !isVisible { orderFrontRegardless() }
            return
        }
        if sameSize {
            setFrameOrigin(frame.origin)
        } else {
            setFrame(frame, display: false, animate: false)
        }
        if !isVisible {
            orderFrontRegardless()
        }
    }

    func focusForTyping() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        model.requestFieldFocus()
    }
}
