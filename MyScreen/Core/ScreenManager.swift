import AppKit
import CoreGraphics

final class ScreenManager: WindowMonitorDelegate, DisplayManagerDelegate, BarrierWindowDelegate {
    let displayManager = DisplayManager()
    private let windowMonitor = WindowMonitor()
    let hotkeyManager = HotkeyManager()
    private var barrierWindows: [UUID: BarrierWindow] = [:]  // keyed by slot UUID
    private(set) var isHidden = false
    private let ownBundleID = Bundle.main.bundleIdentifier ?? "com.myscreen.app"

    private var constrainDebounceTimer: Timer?
    private let animationDuration: TimeInterval = 0.3

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
    }

    func stop() {
        constrainDebounceTimer?.invalidate()
        constrainDebounceTimer = nil
        windowMonitor.stop()
        hotkeyManager.unregister()
        removeAllBarrierWindows()
    }

    func applyConfiguration() {
        Log.info("applyConfiguration called")
        removeAllBarrierWindows()

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
                    windowMonitor.monitorApp(bundleIdentifier: boundApp.bundleIdentifier)
                    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: boundApp.bundleIdentifier)
                    for app in apps { if app.isHidden { app.unhide() } }

                    let targetRect = slotResult.reservedRect
                    let bundleID = boundApp.bundleIdentifier
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.moveBoundApp(bundleIdentifier: bundleID, to: targetRect)
                    }
                }
            }

            if !isHidden {
                let workArea = result.workAreaRect
                let reservedAreas = buildReservedAreas(layout: layout, result: result)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    self.constrainWindows(workArea: workArea, reservedAreas: reservedAreas, excludedBundleIDs: self.excludedBundleIDs())
                }
            }
        }
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
                        self?.hideBoundApp(bundleIdentifier: boundApp.bundleIdentifier)
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
                barrier.orderFront(nil)
                barrierWindows[slot.id] = barrier
                barrier.animateFrame(to: slotResult.dividerRect, duration: animationDuration)

                if let boundApp = slot.boundApp {
                    windowMonitor.monitorApp(bundleIdentifier: boundApp.bundleIdentifier)
                    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: boundApp.bundleIdentifier)
                    for app in apps { if app.isHidden { app.unhide() } }
                    let targetRect = slotResult.reservedRect
                    let bundleID = boundApp.bundleIdentifier
                    DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration * 0.3) { [weak self] in
                        self?.moveBoundApp(bundleIdentifier: bundleID, to: targetRect)
                    }
                }
            }

            let workArea = result.workAreaRect
            let reservedAreas = buildReservedAreas(layout: layout, result: result)
            DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration + 0.1) { [weak self] in
                guard let self = self else { return }
                self.constrainWindows(workArea: workArea, reservedAreas: reservedAreas, excludedBundleIDs: self.excludedBundleIDs())
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
            var layout = AppConfig.shared.layout(for: display.displayID)
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
            moveBoundApp(bundleIdentifier: boundApp.bundleIdentifier, to: slotResult.reservedRect)
        }

        let reservedAreas = buildReservedAreas(layout: updatedLayout, result: result)
        constrainWindows(workArea: result.workAreaRect, reservedAreas: reservedAreas, excludedBundleIDs: excludedBundleIDs())
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
            let activeSlots = layout.slots.filter { $0.isActive }
            guard !activeSlots.isEmpty else { continue }

            let result = LayoutEngine.calculate(screenFrame: display.visibleFrame, slots: layout.slots)
            let reservedAreas = buildReservedAreas(layout: layout, result: result)
            constrainWindows(workArea: result.workAreaRect, reservedAreas: reservedAreas, excludedBundleIDs: excludedBundleIDs())

            for slot in activeSlots {
                guard let boundApp = slot.boundApp, let slotResult = result.slotResults[slot.id] else { continue }
                let axWindows = WindowController.windows(for: boundApp.bundleIdentifier)
                for window in axWindows {
                    guard WindowController.isMovable(window),
                          WindowController.isMainWindow(window),
                          let currentFrame = WindowController.getFrame(window) else { continue }
                    if !rectsApproximatelyEqual(currentFrame, slotResult.reservedRect, tolerance: 5) {
                        WindowController.setFrame(window, to: slotResult.reservedRect)
                    }
                }
            }
        }
    }

    func displayManagerDidDetectChange(_ manager: DisplayManager) {
        applyConfiguration()
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

    private func moveBoundApp(bundleIdentifier: String, to rect: CGRect) {
        let axWindows = WindowController.windows(for: bundleIdentifier)
        for window in axWindows {
            guard WindowController.isMovable(window),
                  WindowController.isMainWindow(window) else { continue }
            WindowController.setFrame(window, to: rect)
        }
    }

    private func hideBoundApp(bundleIdentifier: String) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        for app in apps { app.hide() }
    }

    private func constrainWindows(workArea: CGRect, reservedAreas: [(rect: CGRect, edge: EdgePosition)], excludedBundleIDs: Set<String>) {
        WorkAreaConstraint.constrainAllWindows(workArea: workArea, reservedAreas: reservedAreas, excludedBundleIDs: excludedBundleIDs, ownBundleID: ownBundleID)
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
}
