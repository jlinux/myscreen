import AppKit
import CoreGraphics

final class ScreenManager: WindowMonitorDelegate, DisplayManagerDelegate, BarrierWindowDelegate {
    let displayManager = DisplayManager()
    private let windowMonitor = WindowMonitor()
    let hotkeyManager = HotkeyManager()
    private var barrierWindows: [UUID: BarrierWindow] = [:]  // keyed by slot UUID
    private var monitoredBundleIDs: Set<String> = []
    private(set) var isHidden = false
    private let ownBundleID = Bundle.main.bundleIdentifier ?? "com.myscreen.app"

    private var constrainDebounceTimer: Timer?
    private let animationDuration: TimeInterval = 0.3
    private var spaceChangeObserver: NSObjectProtocol?
    private var appActivationObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var mouseUpMonitor: Any?

    func start() {
        Log.info("ScreenManager starting")
        isHidden = AppConfig.shared.isScreenHidden
        displayManager.delegate = self
        windowMonitor.delegate = self
        applyConfiguration()
        windowMonitor.start()
        hotkeyManager.register { [weak self] in
            self?.toggleVisibility()
        }
        startFullScreenMonitoring()
        startMouseUpMonitor()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                BrightnessManager.shared.reapplySoftwareGamma()
            }
        }
    }

    func stop() {
        constrainDebounceTimer?.invalidate()
        constrainDebounceTimer = nil
        stopMouseUpMonitor()
        stopFullScreenMonitoring()
        if let obs = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
        wakeObserver = nil
        windowMonitor.stop()
        hotkeyManager.unregister()
        removeAllBarrierWindows()
    }

    func applyConfiguration() {
        Log.info("applyConfiguration called")
        removeAllBarrierWindows()
        syncWindowMonitoring()

        for display in displayManager.displays {
            let layout = AppConfig.shared.layout(for: display.displayID)
            let activeSlots = layout.slots.filter { $0.isActive }
            guard !activeSlots.isEmpty else { continue }

            let result = LayoutEngine.calculate(screenFrame: display.visibleFrame, slots: layout.slots)

            if !isHidden {
                for slot in activeSlots {
                    guard let slotResult = result.slotResults[slot.id] else { continue }
                    let reservedSize = reservedSizeForSlot(slot, rect: slotResult.reservedRect)
                    let barrier = BarrierWindow(frame: slotResult.dividerRect, edge: slot.reservedArea.edge)
                    barrier.slotID = slot.id
                    barrier.reservedAreaSize = reservedSize
                    barrier.resizeDelegate = self
                    barrier.orderFront(nil)
                    barrierWindows[slot.id] = barrier
                }
            }

            for slot in activeSlots {
                if let boundApp = slot.boundApp, let slotResult = result.slotResults[slot.id] {
                    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: boundApp.bundleIdentifier)
                    for app in apps { if app.isHidden { app.unhide() } }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.moveBoundWindow(binding: boundApp, to: slotResult.reservedRect)
                    }
                }
            }

            if !isHidden {
                // Constrain immediately and again after a short delay for windows that move later
                let workArea = result.workAreaRect
                let reservedAreas = buildReservedAreas(layout: layout, result: result)
                let excluded = excludedBundleIDs()
                constrainWindows(displayFrame: display.frame, workArea: workArea, reservedAreas: reservedAreas, excludedBundleIDs: excluded)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    self.constrainWindows(displayFrame: display.frame, workArea: workArea, reservedAreas: reservedAreas, excludedBundleIDs: excluded)
                }
            }
        }

        // Boost polling so subsequent window movements are caught quickly
        windowMonitor.boostPolling()
        notifyBindingStateChange()
    }

    // MARK: - F-014: Animated Visibility Toggle

    func toggleVisibility() {
        isHidden.toggle()
        AppConfig.shared.isScreenHidden = isHidden
        AppConfig.shared.save()
        Log.info("toggleVisibility, isHidden=\(isHidden)")
        if isHidden { animateHide() } else { animateShow() }
    }

    private func animateHide() {
        for display in displayManager.displays {
            let layout = AppConfig.shared.layout(for: display.displayID)
            let activeSlots = layout.slots.filter { $0.isActive }
            guard !activeSlots.isEmpty else { continue }

            for slot in activeSlots {
                if let barrier = barrierWindows[slot.id] {
                    let offscreen = offscreenDividerRect(for: display, slot: slot)
                    barrier.animateFrame(to: offscreen, duration: animationDuration) {
                        barrier.orderOut(nil)
                    }
                }
                if let boundApp = slot.boundApp {
                    DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration * 0.5) { [weak self] in
                        self?.hideBoundWindow(binding: boundApp)
                    }
                }
            }
        }
    }

    private func animateShow() {
        for display in displayManager.displays {
            let layout = AppConfig.shared.layout(for: display.displayID)
            let activeSlots = layout.slots.filter { $0.isActive }
            guard !activeSlots.isEmpty else { continue }

            let result = LayoutEngine.calculate(screenFrame: display.visibleFrame, slots: layout.slots)

            for slot in activeSlots {
                guard let slotResult = result.slotResults[slot.id] else { continue }
                let reservedSize = reservedSizeForSlot(slot, rect: slotResult.reservedRect)
                let startRect = offscreenDividerRect(for: display, slot: slot)
                let barrier = BarrierWindow(frame: startRect, edge: slot.reservedArea.edge)
                barrier.slotID = slot.id
                barrier.reservedAreaSize = reservedSize
                barrier.resizeDelegate = self
                barrier.alphaValue = 1.0  // Visible during slide-in animation
                barrier.orderFront(nil)
                barrierWindows[slot.id] = barrier
                barrier.animateFrame(to: slotResult.dividerRect, duration: animationDuration) {
                    barrier.fadeOut(duration: 0.5)
                }

                if let boundApp = slot.boundApp {
                    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: boundApp.bundleIdentifier)
                    for app in apps { if app.isHidden { app.unhide() } }
                    DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration * 0.3) { [weak self] in
                        self?.moveBoundWindow(binding: boundApp, to: slotResult.reservedRect)
                    }
                }
            }

            let workArea = result.workAreaRect
            let reservedAreas = buildReservedAreas(layout: layout, result: result)
            DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration + 0.1) { [weak self] in
                guard let self = self else { return }
                self.constrainWindows(displayFrame: display.frame, workArea: workArea, reservedAreas: reservedAreas, excludedBundleIDs: self.excludedBundleIDs())
            }
        }
    }

    private func offscreenDividerRect(for display: DisplayInfo, slot: ReservedSlot) -> CGRect {
        let singleResult = LayoutEngine.calculate(screenFrame: display.visibleFrame, area: slot.reservedArea)
        let rect = singleResult.dividerRect
        switch slot.reservedArea.edge {
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
        guard let slotID = window.slotID else {
            Log.info("drag: slotID is nil")
            return
        }

        // Find which display owns this slot
        var foundDisplayID: CGDirectDisplayID?
        var foundLayout: ScreenLayout?
        for display in displayManager.displays {
            let layout = AppConfig.shared.layout(for: display.displayID)
            if layout.slot(for: slotID) != nil {
                foundDisplayID = display.displayID
                foundLayout = layout
                break
            }
        }

        guard let displayID = foundDisplayID, var updatedLayout = foundLayout else {
            Log.info("drag: layout not found for slot \(slotID)")
            return
        }
        guard let display = displayManager.display(for: displayID) else { return }

        guard var slot = updatedLayout.slot(for: slotID) else { return }
        slot.reservedArea.size = .pixels(newSize)
        updatedLayout.updateSlot(slot)

        // Save without triggering full applyConfiguration
        AppConfig.shared.setLayout(updatedLayout)

        let result = LayoutEngine.calculate(screenFrame: display.visibleFrame, slots: updatedLayout.slots)
        guard let slotResult = result.slotResults[slotID] else {
            Log.info("drag: slotResult not found for slot \(slotID)")
            return
        }
        window.reservedAreaSize = newSize
        window.updateFrame(cgRect: slotResult.dividerRect)

        // Update other barrier windows too (their positions may shift)
        for otherSlot in updatedLayout.slots where otherSlot.id != slotID && otherSlot.isActive {
            if let otherResult = result.slotResults[otherSlot.id], let otherBarrier = barrierWindows[otherSlot.id] {
                let otherSize = reservedSizeForSlot(otherSlot, rect: otherResult.reservedRect)
                otherBarrier.reservedAreaSize = otherSize
                otherBarrier.updateFrame(cgRect: otherResult.dividerRect)
            }
        }

        if let boundApp = slot.boundApp {
            moveBoundWindow(binding: boundApp, to: slotResult.reservedRect)
        }

        let reservedAreas = buildReservedAreas(layout: updatedLayout, result: result)
        constrainWindows(displayFrame: display.frame, workArea: result.workAreaRect, reservedAreas: reservedAreas, excludedBundleIDs: excludedBundleIDs())
    }

    // MARK: - WindowMonitorDelegate

    func windowMonitorDidDetectChange(_ monitor: WindowMonitor) {
        notifyBindingStateChange()
        guard !isHidden else { return }
        constrainDebounceTimer?.invalidate()
        constrainDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.handleWindowChange()
        }
    }

    private func handleWindowChange() {
        // Skip bound-app repositioning while the user is dragging (mouse button held).
        // The global mouseUp monitor will trigger repositioning when the drag ends.
        let mouseDown = NSEvent.pressedMouseButtons & 0x1 != 0

        for display in displayManager.displays {
            let layout = AppConfig.shared.layout(for: display.displayID)
            let activeSlots = layout.slots.filter { $0.isActive }
            guard !activeSlots.isEmpty else { continue }

            let result = LayoutEngine.calculate(screenFrame: display.visibleFrame, slots: layout.slots)
            let reservedAreas = buildReservedAreas(layout: layout, result: result)
            constrainWindows(displayFrame: display.frame, workArea: result.workAreaRect, reservedAreas: reservedAreas, excludedBundleIDs: excludedBundleIDs())

            for slot in activeSlots {
                guard let boundApp = slot.boundApp, let slotResult = result.slotResults[slot.id] else { continue }
                if mouseDown { continue }
                if let window = WindowController.bestWindow(for: boundApp),
                   let currentFrame = WindowController.getFrame(window),
                   !rectsApproximatelyEqual(currentFrame, slotResult.reservedRect, tolerance: 5) {
                    WindowController.setFrame(window, to: slotResult.reservedRect)
                }
            }
        }
        notifyBindingStateChange()
    }

    // MARK: - Global Mouse-Up Monitor

    private func startMouseUpMonitor() {
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            guard let self = self, !self.isHidden else { return }
            // Small delay to let the window settle at its final position
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.repositionBoundApps()
            }
        }
    }

    private func stopMouseUpMonitor() {
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
        }
    }

    private func repositionBoundApps() {
        for display in displayManager.displays {
            let layout = AppConfig.shared.layout(for: display.displayID)
            let activeSlots = layout.slots.filter { $0.isActive }
            guard !activeSlots.isEmpty else { continue }

            let result = LayoutEngine.calculate(screenFrame: display.visibleFrame, slots: layout.slots)
            for slot in activeSlots {
                guard let boundApp = slot.boundApp, let slotResult = result.slotResults[slot.id] else { continue }
                if let window = WindowController.bestWindow(for: boundApp),
                   let currentFrame = WindowController.getFrame(window),
                   !rectsApproximatelyEqual(currentFrame, slotResult.reservedRect, tolerance: 5) {
                    WindowController.setFrame(window, to: slotResult.reservedRect)
                }
            }
        }
        notifyBindingStateChange()
    }

    func displayManagerDidDetectChange(_ manager: DisplayManager) {
        applyConfiguration()
    }

    // MARK: - Full-Screen Detection

    private func startFullScreenMonitoring() {
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // Delay to allow the full-screen transition to complete and AXFullScreen to update
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                self?.checkFullScreenState()
            }
        }
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.checkFullScreenState()
            }
        }
    }

    private func stopFullScreenMonitoring() {
        if let obs = spaceChangeObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
        if let obs = appActivationObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
        spaceChangeObserver = nil
        appActivationObserver = nil
    }

    private func checkFullScreenState() {
        guard !isHidden else { return }

        let fullScreen = isFrontmostWindowFullScreen()
        Log.info("checkFullScreenState: fullScreen=\(fullScreen)")

        if fullScreen {
            for (_, barrier) in barrierWindows { barrier.orderOut(nil) }
        } else {
            for (_, barrier) in barrierWindows {
                barrier.alphaValue = 0.0  // Stay invisible until hovered
                barrier.orderFront(nil)
            }
        }
    }

    private func isFrontmostWindowFullScreen() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return false }
        if frontmostApp.bundleIdentifier == ownBundleID { return false }

        let pid = frontmostApp.processIdentifier
        let windows = WindowController.windows(for: pid)

        // Method 1: Check AXFullScreen attribute
        if windows.contains(where: { WindowController.isFullScreen($0) }) {
            Log.info("fullscreen detected via AXFullScreen for \(frontmostApp.bundleIdentifier ?? "?")")
            return true
        }

        // Method 2: Fallback — check if any window covers the entire screen
        for window in windows {
            guard WindowController.isMainWindow(window),
                  let frame = WindowController.getFrame(window) else { continue }
            for screen in NSScreen.screens {
                let screenCG = screenToCG(screen.frame)
                if frame.width >= screenCG.width && frame.height >= screenCG.height {
                    Log.info("fullscreen detected via frame size for \(frontmostApp.bundleIdentifier ?? "?")")
                    return true
                }
            }
        }

        return false
    }

    /// Convert NSScreen frame (bottom-left origin) to CG frame (top-left origin).
    private func screenToCG(_ nsFrame: NSRect) -> CGRect {
        CoordinateConverter.nsToCG(nsFrame)
    }

    // MARK: - Helpers

    private func reservedSizeForSlot(_ slot: ReservedSlot, rect: CGRect) -> CGFloat {
        (slot.reservedArea.edge == .left || slot.reservedArea.edge == .right) ? rect.width : rect.height
    }

    private func buildReservedAreas(layout: ScreenLayout, result: LayoutResult) -> [(rect: CGRect, edge: EdgePosition)] {
        layout.slots.filter { $0.isActive }.compactMap { slot in
            guard let slotResult = result.slotResults[slot.id] else { return nil }
            return (rect: slotResult.reservedRect, edge: slot.reservedArea.edge)
        }
    }

    private func moveBoundWindow(binding: AppBinding, to rect: CGRect) {
        guard let window = WindowController.bestWindow(for: binding) else { return }
        if WindowController.isMinimized(window) {
            _ = WindowController.setMinimized(window, to: false)
        }
        WindowController.setFrame(window, to: rect)
    }

    private func hideBoundWindow(binding: AppBinding) {
        if binding.isWindowSpecific,
           let window = WindowController.bestWindow(for: binding),
           WindowController.setMinimized(window, to: true) {
            return
        }

        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: binding.bundleIdentifier)
        for app in apps { app.hide() }
    }

    private func constrainWindows(displayFrame: CGRect, workArea: CGRect, reservedAreas: [(rect: CGRect, edge: EdgePosition)], excludedBundleIDs: Set<String>) {
        WorkAreaConstraint.constrainAllWindows(displayFrame: displayFrame, workArea: workArea, reservedAreas: reservedAreas, excludedBundleIDs: excludedBundleIDs, ownBundleID: ownBundleID)
    }

    private func excludedBundleIDs() -> Set<String> {
        var excluded: Set<String> = [ownBundleID]
        for display in displayManager.displays {
            let layout = AppConfig.shared.layout(for: display.displayID)
            for slot in layout.slots {
                if let bundleID = slot.boundApp?.bundleIdentifier { excluded.insert(bundleID) }
            }
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

    private func syncWindowMonitoring() {
        let desiredBundleIDs = boundBundleIDs()

        for bundleID in monitoredBundleIDs.subtracting(desiredBundleIDs) {
            windowMonitor.unmonitorApp(bundleIdentifier: bundleID)
        }

        for bundleID in desiredBundleIDs.subtracting(monitoredBundleIDs) {
            windowMonitor.monitorApp(bundleIdentifier: bundleID)
        }

        monitoredBundleIDs = desiredBundleIDs
    }

    private func boundBundleIDs() -> Set<String> {
        var bundleIDs: Set<String> = []

        for display in displayManager.displays {
            let layout = AppConfig.shared.layout(for: display.displayID)
            for slot in layout.slots where slot.isActive {
                if let bundleID = slot.boundApp?.bundleIdentifier {
                    bundleIDs.insert(bundleID)
                }
            }
        }

        return bundleIDs
    }

    private func notifyBindingStateChange() {
        NotificationCenter.default.post(name: .myScreenBindingStateDidChange, object: nil)
    }
}
