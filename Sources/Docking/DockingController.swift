import AppKit
import ApplicationServices
import QuartzCore

@MainActor
final class AppModel: ObservableObject {
    @Published var permissions = PermissionGate.current()
    @Published var trackedWindowCount = 0
}

/// CADisplayLink callbacks arrive on the main thread but are not @MainActor-isolated.
final class DisplayLinkProxy: NSObject, @unchecked Sendable {
    static let shared = DisplayLinkProxy()

    @objc func tick(_ link: CADisplayLink) {
        MainActor.assumeIsolated {
            DockingController.shared.syncFrames()
        }
    }
}

@MainActor
final class DockingController {
    static let shared = DockingController()

    let appModel = AppModel()

    private var panels: [WindowKey: StageBarPanel] = [:]
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var contentTimer: Timer?
    private var displayLink: CADisplayLink?
    private var scriptingWindows: [ScriptingFinderWindow] = []
    private var frontSelection: [SelectedItem] = []
    private var axElements: [WindowKey: AXUIElement] = [:]
    private var lastScriptingRefresh: Date = .distantPast
    private var scriptingInFlight = false
    private var lastPermissionCheck: Date = .distantPast
    private var refreshPending = false
    private var missingFrameStreak = 0
    private var movingUntil: Date = .distantPast
    private var dockSettle: [WindowKey: (frame: CGRect, since: Date)] = [:]
    private var dockApplied: [WindowKey: (frame: CGRect, at: Date)] = [:]
    private var desktopSummoned = false
    private var desktopSummonedAt = Date.distantPast

    private init() {}

    func start() {
        NSLog("[Understage] DockingController starting...")
        VendorSettings.shared.applyHotKey()
        let perms = PermissionGate.current()
        NSLog("[Understage] Initial permissions: accessibility=%d, finderAutomation=%d",
              perms.accessibility ? 1 : 0, perms.finderAutomation ? 1 : 0)
        refresh()
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                DockingController.shared.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        contentTimer = timer
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                DockingController.shared.refresh()
            }
        }
    }

    func toggleOrFocusFrontmostBar() {
        if NSApp.isActive && panels.values.contains(where: { $0.isKeyWindow }) {
            FinderAX.activateFinder()
            return
        }

        summonDesktopBar()
        refresh()

        if let focused = FinderAX.focusedWindow(), let panel = panelMatching( focused) {
            desktopSummoned = false
            panel.focusForTyping()
            return
        }

        if let desktop = panels[.desktop] {
            desktop.focusForTyping()
            return
        }

        if let panel = panels.values.first {
            panel.focusForTyping()
        }
    }

    func prefillFrontBar(_ query: String, submit: Bool) {
        summonDesktopBar()
        refresh()
        let panel: StageBarPanel?
        if let focused = FinderAX.focusedWindow(), let existing = panelMatching( focused) {
            panel = existing
        } else if let desktop = panels[.desktop] {
            panel = desktop
        } else {
            panel = panels.values.first
        }
        guard let panel else { return }
        panel.focusForTyping()
        panel.model.query = query
        if submit {
            panel.model.submit()
        }
    }

    func refresh() {
        if Date() < movingUntil {
            syncFrames()
            return
        }
        let now = Date()
        if now.timeIntervalSince(lastPermissionCheck) > 2 || panels.isEmpty {
            lastPermissionCheck = now
            let currentPerms = PermissionGate.current()
            if currentPerms != appModel.permissions {
                NSLog("[Understage] Permissions changed: accessibility=%d, finderAutomation=%d",
                      currentPerms.accessibility ? 1 : 0, currentPerms.finderAutomation ? 1 : 0)
                appModel.permissions = currentPerms
            }
        }
        installObserverIfNeeded()

        let finderFront = FinderAX.isFinderFrontmost()

        // The desktop bar is summon-only; drop it once it lost focus.
        if desktopSummoned,
           !NSApp.isActive,
           panels[.desktop]?.isKeyWindow != true,
           Date().timeIntervalSince(desktopSummonedAt) > 1
        {
            desktopSummoned = false
        }

        guard appModel.permissions.accessibility else {
            pauseDisplayLink()
            if panels.isEmpty {
                NSLog("[Understage] Accessibility not granted, showing onboarding bar")
            }
            showOnboardingBar()
            return
        }

        // Stage Manager keeps other stages' windows in the window list, and the
        // panel itself activates this app, so allow both frontmost states.
        guard finderFront || NSApp.isActive || desktopSummoned else {
            pauseDisplayLink()
            desktopSummoned = false
            hideAll()
            if appModel.trackedWindowCount != 0 {
                appModel.trackedWindowCount = 0
            }
            return
        }

        let axWindows = FinderAX.windows().filter { !$0.isMinimized }
        let onScreenFrames = onScreenFinderFrames()
        refreshScriptingIfNeeded()

        var desired: [WindowKey: StageContext] = [:]
        var elements: [WindowKey: AXUIElement] = [:]
        var consumed = Set<WindowKey>()
        let frontIndex = frontWindowIndex(in: axWindows)
        for (index, window) in axWindows.enumerated() {
            // Stage Manager renders other Spaces' windows as thumbnails and AX may
            // still report the parked frame, so trust only a live frame at the same spot.
            if case .cgWindow(let id) = window.key {
                guard let live = onScreenFrames[id],
                      framesClose(AXGeometry.cocoaRect(axPosition: live.origin, axSize: live.size),
                                  window.cocoaFrame, tolerance: 60)
                else { continue }
            }
            if case .fallback = window.key, !finderFront {
                continue
            }
            guard stageVisible(window.cocoaFrame) else { continue }
            let key = stableKey(for: window, consumed: consumed)
            consumed.insert(key)
            let folder = window.documentURL
                ?? FinderScripting.matchTarget(
                    title: window.title,
                    cocoaSize: window.cocoaFrame.size,
                    windows: scriptingWindows
                )
            var selected = window.selected
            if selected.isEmpty, index == frontIndex || axWindows.count == 1 {
                selected = frontSelection
            }
            desired[key] = StageContext(
                windowID: cgWindowID(key),
                folderURL: folder,
                folderName: folder?.lastPathComponent ?? window.title,
                selected: selected,
                title: window.title,
                cocoaFrame: window.cocoaFrame,
                isDesktop: false
            )
            elements[key] = window.element
        }
        axElements = elements

        if !desired.isEmpty {
            desktopSummoned = false
        }

        if desired.isEmpty && !finderFront && !desktopSummoned {
            pauseDisplayLink()
            hideAll()
            if appModel.trackedWindowCount != 0 {
                appModel.trackedWindowCount = 0
            }
            return
        }

        if desired.isEmpty && desktopSummoned {
            if let screen = NSScreen.main {
                let folder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
                desired[.desktop] = StageContext(
                    windowID: 0,
                    folderURL: folder,
                    folderName: "Desktop",
                    selected: frontSelection,
                    title: "Desktop",
                    cocoaFrame: screen.visibleFrame,
                    isDesktop: true
                )
            }
        }

        for key in panels.keys where desired[key] == nil {
            panels[key]?.orderOut(nil)
            panels[key] = nil
        }

        for (key, context) in desired {
            let panel = panels[key] ?? makePanel()
            panels[key] = panel
            if panel.model.permissions != appModel.permissions {
                panel.model.permissions = appModel.permissions
            }
            if let old = panel.model.context, old.sameContent(as: context) {
                // Frame-only changes are applied by the display link.
            } else {
                panel.model.context = context
            }
            place(panel, under: context.cocoaFrame, desktop: context.isDesktop, key: key, element: elements[key])
        }

        if appModel.trackedWindowCount != desired.count {
            NSLog("[Understage] Tracked Finder window count changed: %d -> %d", appModel.trackedWindowCount, desired.count)
            appModel.trackedWindowCount = desired.count
        }
        missingFrameStreak = 0
        startDisplayLinkIfNeeded()
        syncFrames()
    }

    func syncFrames() {
        guard !panels.isEmpty else { return }
        guard let pid = FinderAX.finderPID else { return }
        let frames = CGWindowFrames.onScreen(ownerPID: pid)
        var missed = 0
        for (key, panel) in panels {
            switch key {
            case .cgWindow(let id):
                guard let cgRect = frames[id] else {
                    missed += 1
                    continue
                }
                let cocoa = AXGeometry.cocoaRect(
                    axPosition: cgRect.origin,
                    axSize: cgRect.size
                )
                guard stageVisible(cocoa) else {
                    panel.orderOut(nil)
                    continue
                }
                if place(panel, under: cocoa, desktop: false, key: key, element: axElements[key]) {
                    movingUntil = Date().addingTimeInterval(0.2)
                }
            case .desktop:
                if let screen = NSScreen.main {
                    panel.place(frame: BarPlacement.desktopBarFrame(on: screen, height: panel.model.barHeight))
                }
            case .fallback:
                guard let element = axElements[key],
                      let position = AXAttr.point(element, "AXPosition"),
                      let size = AXAttr.size(element, "AXSize")
                else { continue }
                let cocoa = AXGeometry.cocoaRect(axPosition: position, axSize: size)
                if place(panel, under: cocoa, desktop: false, key: key, element: element) {
                    movingUntil = Date().addingTimeInterval(0.2)
                }
            }
        }
        if missed > 0 {
            missingFrameStreak += 1
            if missingFrameStreak >= 8 {
                missingFrameStreak = 0
                scheduleRefresh()
            }
        } else {
            missingFrameStreak = 0
        }
    }

    @discardableResult
    private func place(
        _ panel: StageBarPanel,
        under window: CGRect,
        desktop: Bool,
        key: WindowKey,
        element: AXUIElement?
    ) -> Bool {
        let screen = AXGeometry.screen(containing: window) ?? NSScreen.main
        guard let screen else { return false }
        let height = panel.model.barHeight
        let host = desktop
            ? window
            : windowClearingDock(key: key, element: element, window: window, screen: screen, barHeight: height)
        let frame = desktop
            ? BarPlacement.desktopBarFrame(on: screen, height: height)
            : BarPlacement.frame(forWindow: host, on: screen, height: height)
        let moved = abs(panel.frame.minX - frame.minX) > 0.5 || abs(panel.frame.minY - frame.minY) > 0.5
        panel.place(frame: frame)
        return moved
    }

    /// When the bar would cover the Dock, shorten the Finder window from the
    /// bottom once the frame has sat still. Returns the window rect the bar
    /// should follow, which may be the size just requested.
    private func windowClearingDock(
        key: WindowKey,
        element: AXUIElement?,
        window: CGRect,
        screen: NSScreen,
        barHeight: CGFloat
    ) -> CGRect {
        guard let target = BarPlacement.windowClearingDock(
            window: window,
            visible: screen.visibleFrame,
            height: barHeight,
            overlap: BarPlacement.overlap
        ) else {
            dockSettle[key] = nil
            dockApplied[key] = nil
            return window
        }
        if let applied = dockApplied[key] {
            if framesClose(window, applied.frame) {
                dockApplied[key] = nil
                dockSettle[key] = nil
                return window
            }
            if Date().timeIntervalSince(applied.at) < 1 {
                return applied.frame
            }
            dockApplied[key] = nil
        }
        guard let element, AXAttr.bool(element, "AXFullScreen") != true else { return window }
        let now = Date()
        if let settle = dockSettle[key], framesClose(settle.frame, window) {
            guard now.timeIntervalSince(settle.since) >= 0.2 else { return window }
        } else {
            dockSettle[key] = (window, now)
            return window
        }
        guard FinderAX.setCocoaFrame(element, target) else {
            dockSettle[key] = (window, now)
            return window
        }
        dockApplied[key] = (target, now)
        dockSettle[key] = (target, now)
        return target
    }

    /// Stage Manager parks inactive stages off-screen (negative x). A bar
    /// following one of those windows would float over an empty backdrop.
    private func stageVisible(_ frame: CGRect) -> Bool {
        NSScreen.screens.contains { $0.frame.intersects(frame) }
    }

    private func framesClose(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(lhs.minX - rhs.minX) < tolerance
            && abs(lhs.minY - rhs.minY) < tolerance
            && abs(lhs.width - rhs.width) < tolerance
            && abs(lhs.height - rhs.height) < tolerance
    }

    private func onScreenFinderFrames() -> [CGWindowID: CGRect] {
        guard let pid = FinderAX.finderPID else { return [:] }
        return CGWindowFrames.onScreen(ownerPID: pid)
    }

    /// The desktop bar is summon-only: an empty Space must stay empty.
    private func summonDesktopBar() {
        desktopSummoned = true
        desktopSummonedAt = Date()
    }

    private func showOnboardingBar() {
        let key = WindowKey.fallback("onboarding")
        let panel = panels[key] ?? makePanel()
        panels[key] = panel
        for other in panels.keys where other != key {
            panels[other]?.orderOut(nil)
            panels[other] = nil
        }
        panel.model.permissions = appModel.permissions
        panel.model.context = nil
        if let screen = NSScreen.main {
            panel.place(frame: BarPlacement.desktopBarFrame(on: screen))
        }
        appModel.trackedWindowCount = 0
    }

    private func hideAll() {
        for panel in panels.values {
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> StageBarPanel {
        StageBarPanel(model: StageBarModel(permissions: appModel.permissions))
    }

    private func cgWindowID(_ key: WindowKey) -> UInt32 {
        if case .cgWindow(let id) = key { return id }
        return 0
    }

    private func refreshScriptingIfNeeded() {
        guard appModel.permissions.finderAutomation else { return }
        guard !scriptingInFlight else { return }
        let now = Date()
        guard now.timeIntervalSince(lastScriptingRefresh) > 0.4 else { return }
        lastScriptingRefresh = now
        scriptingInFlight = true
        Task.detached {
            let shot = FinderScripting.snapshot()
            await MainActor.run {
                DockingController.shared.scriptingInFlight = false
                DockingController.shared.scriptingWindows = shot.windows
                DockingController.shared.frontSelection = shot.frontSelection
            }
        }
    }

    private func frontWindowIndex(in windows: [AXFinderWindow]) -> Int? {
        guard let front = scriptingWindows.first else {
            return windows.count == 1 ? 0 : nil
        }
        let matches = windows.enumerated().filter { $0.element.title == front.name }
        if matches.count == 1 { return matches[0].offset }
        if matches.isEmpty { return windows.count == 1 ? 0 : nil }
        let size = CGSize(width: front.width, height: front.height)
        return matches.min { lhs, rhs in
            sizeDistance(lhs.element.cocoaFrame.size, size) < sizeDistance(rhs.element.cocoaFrame.size, size)
        }?.offset
    }

    private func sizeDistance(_ lhs: CGSize, _ rhs: CGSize) -> Double {
        let dw = lhs.width - rhs.width
        let dh = lhs.height - rhs.height
        return dw * dw + dh * dh
    }

    private func stableKey(for window: AXFinderWindow, consumed: Set<WindowKey>) -> WindowKey {
        if case .cgWindow = window.key { return window.key }
        let candidates = panels.keys.filter { key in
            guard case .fallback = key, !consumed.contains(key) else { return false }
            return panels[key]?.model.context?.title == window.title
        }
        if candidates.count == 1, let only = candidates.first { return only }
        if candidates.count > 1 {
            return candidates.min { lhs, rhs in
                centerDistance(panels[lhs]?.frame ?? .zero, window.cocoaFrame)
                    < centerDistance(panels[rhs]?.frame ?? .zero, window.cocoaFrame)
            } ?? window.key
        }
        if !consumed.contains(window.key) { return window.key }
        return .fallback("\(window.title)|\(UUID().uuidString)")
    }

    private func centerDistance(_ panel: CGRect, _ window: CGRect) -> CGFloat {
        let dx = panel.midX - window.midX
        let dy = panel.midY - window.midY
        return dx * dx + dy * dy
    }

    private func panelMatching(_ window: AXFinderWindow) -> StageBarPanel? {
        if let panel = panels[window.key] { return panel }
        guard case .fallback = window.key else { return nil }
        let matches = panels.filter { key, panel in
            guard case .fallback = key else { return false }
            return panel.model.context?.title == window.title
        }
        return matches.min { lhs, rhs in
            centerDistance(lhs.value.frame, window.cocoaFrame) < centerDistance(rhs.value.frame, window.cocoaFrame)
        }?.value
    }

    private func startDisplayLinkIfNeeded() {
        if displayLink != nil {
            displayLink?.isPaused = false
            return
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let link = screen.displayLink(
            target: DisplayLinkProxy.shared,
            selector: #selector(DisplayLinkProxy.tick(_:))
        )
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func pauseDisplayLink() {
        displayLink?.isPaused = true
    }

    private func installObserverIfNeeded() {
        guard let pid = FinderAX.finderPID else { return }
        if observedPID == pid, observer != nil { return }
        observedPID = pid
        var newObserver: AXObserver?
        let error = AXObserverCreate(pid, { _, _, _, _ in
            MainActor.assumeIsolated {
                DockingController.shared.scheduleRefresh()
            }
        }, &newObserver)
        guard error == .success, let newObserver, let app = FinderAX.applicationElement() else { return }
        observer = newObserver
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(newObserver),
            .commonModes
        )
        let notifications = [
            "AXWindowCreated",
            "AXUIElementDestroyed",
            "AXWindowMiniaturized",
            "AXWindowDeminiaturized",
            "AXFocusedWindowChanged",
            "AXTitleChanged",
            "AXApplicationHidden",
            "AXApplicationShown",
        ]
        for name in notifications {
            AXObserverAddNotification(newObserver, app, name as CFString, nil)
        }
    }

    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in
            self?.refreshPending = false
            self?.refresh()
        }
    }
}
