import Carbon
import Foundation

enum HotKeyOption: String, CaseIterable, Identifiable, Codable, Sendable {
    case optionSpace
    case optionCommandU
    case controlSpace
    case disabled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .optionSpace: L10n.tr("Option + Space (⌥Space)")
        case .optionCommandU: L10n.tr("Option + Command + U (⌥⌘U)")
        case .controlSpace: L10n.tr("Control + Space (^Space)")
        case .disabled: L10n.tr("Disabled")
        }
    }

    var keyCode: UInt32? {
        switch self {
        case .optionSpace, .controlSpace: UInt32(kVK_Space)
        case .optionCommandU: UInt32(kVK_ANSI_U)
        case .disabled: nil
        }
    }

    var modifiers: UInt32? {
        switch self {
        case .optionSpace: UInt32(optionKey)
        case .optionCommandU: UInt32(optionKey | cmdKey)
        case .controlSpace: UInt32(controlKey)
        case .disabled: nil
        }
    }
}

final class GlobalHotKeyManager: @unchecked Sendable {
    static let shared = GlobalHotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onTrigger: (@MainActor () -> Void)?
    private(set) var registered = true

    private init() {}

    func register(option: HotKeyOption, onTrigger: @escaping @MainActor () -> Void) {
        unregister()
        self.onTrigger = onTrigger
        guard let keyCode = option.keyCode, let modifiers = option.modifiers else {
            registered = true
            return
        }
        registered = false

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr && hotKeyID.id == 1 {
                NSLog("[Understage] Global hotkey event triggered")
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    manager.onTrigger?()
                }
            }
            return noErr
        }

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            handler,
            1,
            &eventType,
            userData,
            &eventHandler
        )
        guard installStatus == noErr else {
            NSLog("[Understage] Global hotkey handler failed (%d)", installStatus)
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x554E4453), id: 1) // 'UNDS'
        let regStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        registered = regStatus == noErr
        NSLog("[Understage] Global hotkey registered for %@ (status: %d)", option.displayName, regStatus)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
