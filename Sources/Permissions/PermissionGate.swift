import ApplicationServices
import AppKit

struct PermissionState: Equatable {
    var accessibility: Bool
    var finderAutomation: Bool

    var allGranted: Bool { accessibility && finderAutomation }
}

enum PermissionGate {
    static func current() -> PermissionState {
        PermissionState(
            accessibility: AXIsProcessTrusted(),
            finderAutomation: finderAutomationGranted(prompt: false)
        )
    }

    static func promptAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func promptFinderAutomation() {
        _ = finderAutomationGranted(prompt: true)
    }

    private static func finderAutomationGranted(prompt: Bool) -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        guard let aeDesc = target.aeDesc else { return false }
        let status = AEDeterminePermissionToAutomateTarget(
            aeDesc,
            typeWildCard,
            typeWildCard,
            prompt
        )
        return status == noErr
    }
}
