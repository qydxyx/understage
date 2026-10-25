import SwiftUI

@main
struct UnderstageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Understage", systemImage: "rectangle.bottomhalf.inset.filled") {
            MenuBarView(appModel: DockingController.shared.appModel)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DockingController.shared.start()
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers == ","
            {
                Task { @MainActor in
                    SettingsPresenter.shared.open()
                }
                return nil
            }
            return event
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DockingController.shared.refresh()
        return false
    }
}
