import AppKit
import CoreGraphics

final class ScreenManager: WindowMonitorDelegate, DisplayManagerDelegate, BarrierWindowDelegate {
    let displayManager = DisplayManager()
    private let windowMonitor = WindowMonitor()
    let hotkeyManager = HotkeyManager()
    private var barrierWindows: [CGDirectDisplayID: BarrierWindow] = [:]
    private(set) var isHidden = false
    private let ownBundleID = Bundle.main.bundleIdentifier ?? "com.myscreen.app"

    private var constrainDebounceTimer: Timer?
    private let animationDuration: TimeInterval = 0.3

    func start() {
        Log.info("ScreenManager starting")
        displayManager.delegate = self
        windowMonitor.delegate = self
        applyConfiguration()
        windowMonitor.start()
        hotkeyManager.register { [weak self] in
            self?.toggleVisibility()
        }
    }

    func stop() {
        windowMonitor.stop()
        hotkeyManager.unregister()
        removeAllBarrierWindows()
    }

    func applyConfiguration() {
        Log.info("applyConfiguration called")
        removeAllBarrierWindows()

        for display in displayManager.displays {
            let layout = AppConfig.shared.layout(for: display.displayID)
            guard layout.isActive else { continue }

            let result = LayoutEngine.calculate(screenFrame: display.visibleFrame, area: layout.reservedArea)

            if !isHidden {
                let reservedSize = (layout.reservedArea.edge == .left || layout.reservedArea.edge == .right) ? result.reservedRect.width : result.reservedRect.height
                let barrier = BarrierWindow(frame: result.dividerRect, edge: layout.reservedArea.edge)
                barrier.reservedAreaSize = reservedSize
                barrier.resizeDelegate = self
                barrier.orderFront(nil)
                barrierWindows[display.displayID] = barrier
            }

            if let boundApp = layout.boundApp {
                windowMonitor.monitorApp(bundleIdentifier: boundApp.bundleIdentifier)
                let apps = NSRunningApplication.runningApplications(withBundleIdentifier: boundApp.bundleIdentifier)
                for app in apps { if app.isHidden { app.unhide() } }

                let targetRect = result.reservedRect
                let bundleID = boundApp.bundleIdentifier
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.moveBoundApp(bundleIdentifier: bundleID, to: targetRect)
                }
            }

            if !isHidden {
                let workArea = result.workAreaRect
                let reservedArea = result.reservedRect
                let edge = layout.reservedArea.edge
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    self.constrainWindows(workArea: workArea, reservedArea: reservedArea, edge: edge, excludedBundleIDs: self.excludedBundleIDs())
                }
            }
        }
    }

    // MARK: - F-014: Animated Visibility Toggle

    func toggleVisibility() {
        isHidden.toggle()
        Log.info("toggleVisibility, isHidden=\(isHidden)")
        if isHidden { animateHide() } else { animateShow() }
    }

    private func animateHide() {
        for display in displayManager.displays {
            let layout = AppConfig.shared.layout(for: display.displayID)
            guard layout.isActive else { continue }

            if let barrier = barrierWindows[display.displayID] {
                let offscreen = offscreenRect(for: display, edge: layout.reservedArea.edge, layout: layout)
                barrier.animateFrame(to: offscreen, duration: animationDuration) {
                    barrier.orderOut(nil)
                }
            }

            if let boundApp = layout.boundApp {
                DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration * 0.5) {
                    self.hideBoundApp(bundleIdentifier: boundApp.bundleIdentifier)
                }
            }
        }
    }

    private func animateShow() {
        for display in displayManager.displays {
            let layout = AppConfig.shared.layout(for: display.displayID)
            guard layout.isActive else { continue }

            let result = LayoutEngine.calculate(screenFrame: display.visibleFrame, area: layout.reservedArea)
            let reservedSize = (layout.reservedArea.edge == .left || layout.reservedArea.edge == .right) ? result.reservedRect.width : result.reservedRect.height
            let startRect = offscreenRect(for: display, edge: layout.reservedArea.edge, layout: layout)
            let barrier = BarrierWindow(frame: startRect, edge: layout.reservedArea.edge)
            barrier.reservedAreaSize = reservedSize
            barrier.resizeDelegate = self
            barrier.orderFront(nil)
            barrierWindows[display.displayID] = barrier
            barrier.animateFrame(to: result.dividerRect, duration: animationDuration)

            if let boundApp = layout.boundApp {
                windowMonitor.monitorApp(bundleIdentifier: boundApp.bundleIdentifier)
                let apps = NSRunningApplication.runningApplications(withBundleIdentifier: boundApp.bundleIdentifier)
                for app in apps { if app.isHidden { app.unhide() } }
                let targetRect = result.reservedRect
                let bundleID = boundApp.bundleIdentifier
                DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration * 0.3) { [weak self] in
                    self?.moveBoundApp(bundleIdentifier: bundleID, to: targetRect)
                }
            }

            let workArea = result.workAreaRect
            let reservedArea = result.reservedRect
            let edge = layout.reservedArea.edge
            DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration + 0.1) { [weak self] in
                guard let self = self else { return }
                self.constrainWindows(workArea: workArea, reservedArea: reservedArea, edge: edge, excludedBundleIDs: self.excludedBundleIDs())
            }
        }
    }

    private func offscreenRect(for display: DisplayInfo, edge: EdgePosition, layout: ScreenLayout) -> CGRect {
        let result = LayoutEngine.calculate(screenFrame: display.visibleFrame, area: layout.reservedArea)
        let rect = result.dividerRect
        switch edge {
        case .right:
            return CGRect(x: display.visibleFrame.maxX, y: rect.origin.y, width: rect.width, height: rect.height)
        case .left:
            return CGRect(x: display.visibleFrame.origin.x - rect.width, y: rect.origin.y, width: rect.width, height: rect.height)
        case .top:
            return CGRect(x: rect.origin.x, y: display.visibleFrame.origin.y - rect.height, width: rect.width, height: rect.height)
        case .bottom:
            return CGRect(x: rect.origin.x, y: display.visibleFrame.maxY, width: rect.width, height: rect.height)
        }
    }

    // MARK: - F-010: BarrierWindowDelegate

    func barrierWindow(_ window: BarrierWindow, didDragToSize newSize: CGFloat) {
        guard let (displayID, _) = barrierWindows.first(where: { $0.value === window }) else { return }
        guard let display = displayManager.display(for: displayID) else { return }

        var layout = AppConfig.shared.layout(for: displayID)
        layout.reservedArea.size = .pixels(newSize)
        AppConfig.shared.setLayout(layout)

        let result = LayoutEngine.calculate(screenFrame: display.visibleFrame, area: layout.reservedArea)
        window.reservedAreaSize = newSize
        window.updateFrame(cgRect: result.dividerRect)

        if let boundApp = layout.boundApp {
            moveBoundApp(bundleIdentifier: boundApp.bundleIdentifier, to: result.reservedRect)
        }
        constrainWindows(workArea: result.workAreaRect, reservedArea: result.reservedRect, edge: layout.reservedArea.edge, excludedBundleIDs: excludedBundleIDs())
    }

    // MARK: - WindowMonitorDelegate

    func windowMonitorDidDetectChange(_ monitor: WindowMonitor) {
        guard !isHidden else { return }
        constrainDebounceTimer?.invalidate()
        constrainDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.handleWindowChange()
        }
    }

    private func handleWindowChange() {
        for display in displayManager.displays {
            let layout = AppConfig.shared.layout(for: display.displayID)
            guard layout.isActive else { continue }

            let result = LayoutEngine.calculate(screenFrame: display.visibleFrame, area: layout.reservedArea)
            constrainWindows(workArea: result.workAreaRect, reservedArea: result.reservedRect, edge: layout.reservedArea.edge, excludedBundleIDs: excludedBundleIDs())

            if let boundApp = layout.boundApp {
                let axWindows = WindowController.windows(for: boundApp.bundleIdentifier)
                for window in axWindows {
                    guard WindowController.isMovable(window), let currentFrame = WindowController.getFrame(window) else { continue }
                    if !rectsApproximatelyEqual(currentFrame, result.reservedRect, tolerance: 5) {
                        WindowController.setFrame(window, to: result.reservedRect)
                    }
                }
            }
        }
    }

    func displayManagerDidDetectChange(_ manager: DisplayManager) {
        applyConfiguration()
    }

    private func moveBoundApp(bundleIdentifier: String, to rect: CGRect) {
        let axWindows = WindowController.windows(for: bundleIdentifier)
        for window in axWindows {
            guard WindowController.isMovable(window) else { continue }
            WindowController.setFrame(window, to: rect)
        }
    }

    private func hideBoundApp(bundleIdentifier: String) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        for app in apps { app.hide() }
    }

    private func constrainWindows(workArea: CGRect, reservedArea: CGRect, edge: EdgePosition, excludedBundleIDs: Set<String>) {
        WorkAreaConstraint.constrainAllWindows(workArea: workArea, reservedArea: reservedArea, edge: edge, excludedBundleIDs: excludedBundleIDs, ownBundleID: ownBundleID)
    }

    private func excludedBundleIDs() -> Set<String> {
        var excluded: Set<String> = [ownBundleID]
        for display in displayManager.displays {
            let layout = AppConfig.shared.layout(for: display.displayID)
            if let bundleID = layout.boundApp?.bundleIdentifier { excluded.insert(bundleID) }
        }
        return excluded
    }

    private func removeAllBarrierWindows() {
        for (_, barrier) in barrierWindows { barrier.orderOut(nil) }
        barrierWindows.removeAll()
    }

    private func rectsApproximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        abs(a.origin.x - b.origin.x) < tolerance && abs(a.origin.y - b.origin.y) < tolerance &&
        abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }
}
