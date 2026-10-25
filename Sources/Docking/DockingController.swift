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
    private var lastScriptingRefresh: Date = .distantPast
    private var refreshPending = false
    private var missingFrameStreak = 0
    private var movingUntil: Date = .distantPast

    private init() {}

    func start() {
        refresh()
        let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
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

    func refresh() {
        if Date() < movingUntil {
            syncFrames()
            return
        }
        appModel.permissions = PermissionGate.current()
        installObserverIfNeeded()

        let ourAppIsActive = NSApp.isActive
        let finderFront = FinderAX.isFinderFrontmost()
        let barIsKey = panels.values.contains { $0.isKeyWindow }

        guard appModel.permissions.accessibility else {
            pauseDisplayLink()
            showOnboardingBar()
            return
        }

        let axWindows = FinderAX.windows().filter { !$0.isMinimized }
        refreshScriptingIfNeeded()

        var desired: [WindowKey: StageContext] = [:]
        for window in axWindows {
            let folder = window.documentURL
                ?? FinderScripting.matchTarget(
                    title: window.title,
                    cocoaSize: window.cocoaFrame.size,
                    windows: scriptingWindows
                )
            desired[window.key] = StageContext(
                windowID: cgWindowID(window.key),
                folderURL: folder,
                folderName: folder?.lastPathComponent ?? window.title,
                selected: window.selected,
                title: window.title,
                cocoaFrame: window.cocoaFrame,
                isDesktop: false
            )
        }

        if axWindows.isEmpty && finderFront {
            if let screen = NSScreen.main {
                let folder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
                desired[.desktop] = StageContext(
                    windowID: 0,
                    folderURL: folder,
                    folderName: "Desktop",
                    selected: [],
                    title: "Desktop",
                    cocoaFrame: screen.visibleFrame,
                    isDesktop: true
                )
            }
        }

        let shouldShow = finderFront || ourAppIsActive || barIsKey
        if !shouldShow {
            pauseDisplayLink()
            hideAll()
            if appModel.trackedWindowCount != 0 {
                appModel.trackedWindowCount = 0
            }
            return
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
            place(panel, under: context.cocoaFrame, desktop: context.isDesktop)
        }

        if appModel.trackedWindowCount != desired.count {
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
                if place(panel, under: cocoa, desktop: false) {
                    movingUntil = Date().addingTimeInterval(0.2)
                }
            case .desktop:
                if let screen = NSScreen.main {
                    panel.place(frame: BarPlacement.desktopBarFrame(on: screen, height: panel.model.barHeight))
                }
            case .fallback:
                continue
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
    private func place(_ panel: StageBarPanel, under window: CGRect, desktop: Bool) -> Bool {
        let screen = AXGeometry.screen(containing: window) ?? NSScreen.main
        guard let screen else { return false }
        let height = panel.model.barHeight
        let frame = desktop
            ? BarPlacement.desktopBarFrame(on: screen, height: height)
            : BarPlacement.frame(forWindow: window, on: screen, height: height)
        let moved = abs(panel.frame.minX - frame.minX) > 0.5 || abs(panel.frame.minY - frame.minY) > 0.5
        panel.place(frame: frame)
        return moved
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
        let now = Date()
        guard now.timeIntervalSince(lastScriptingRefresh) > 0.4 else { return }
        lastScriptingRefresh = now
        Task.detached {
            let windows = FinderScripting.listWindows()
            await MainActor.run {
                DockingController.shared.scriptingWindows = windows
            }
        }
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
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
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
