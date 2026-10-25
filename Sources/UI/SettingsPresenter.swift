import AppKit
import SwiftUI

@MainActor
final class SettingsPresenter: NSObject, NSWindowDelegate {
    static let shared = SettingsPresenter()

    private var window: NSWindow?

    func open() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            hosting.sizingOptions = [.preferredContentSize]
            let win = NSWindow(contentViewController: hosting)
            win.title = String(localized: "Understage Settings")
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.setContentSize(NSSize(width: 480, height: 560))
            win.center()
            win.isReleasedWhenClosed = false
            win.hidesOnDeactivate = false
            win.level = .floating
            win.delegate = self
            window = win
        }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
