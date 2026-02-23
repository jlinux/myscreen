import AppKit
import CoreGraphics

/// Central coordinator connecting all components.
final class ScreenManager: WindowMonitorDelegate, DisplayManagerDelegate {
    let displayManager = DisplayManager()
    private let windowMonitor = WindowMonitor()
    private let hotkeyManager = HotkeyManager()
    private var barrierWindows: [CGDirectDisplayID: BarrierWindow] = [:]
    private var isHidden = false
    private let ownBundleID = Bundle.main.bundleIdentifier ?? "com.myscreen.app"

    /// Debounce timer to avoid processing window changes too frequently.
    private var constrainDebounceTimer: Timer?

    func start() {
        Log.info("ScreenManager starting, ownBundleID=\(ownBundleID)")
        Log.info("Displays count=\(displayManager.displays.count)")
        for d in displayManager.displays {
            Log.info("  Display '\(d.localizedName)' id=\(d.displayID) frame=\(d.frame) visible=\(d.visibleFrame) isMain=\(d.isMain)")
        }

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

    /// Called when configuration changes (from UI or externally).
    func applyConfiguration() {
        Log.info("applyConfiguration called, isHidden=\(isHidden)")
        removeAllBarrierWindows()

        for display in displayManager.displays {
            let layout = AppConfig.shared.layout(for: display.displayID)
            Log.info("Display '\(display.localizedName)' id=\(display.displayID) isActive=\(layout.isActive) edge=\(layout.reservedArea.edge.rawValue) boundApp=\(layout.boundApp?.displayName ?? "none")")

            guard layout.isActive else { continue }

            let result = LayoutEngine.calculate(
                screenFrame: display.visibleFrame,
                area: layout.reservedArea
            )

            Log.info("  reservedRect=\(result.reservedRect)")
            Log.info("  workAreaRect=\(result.workAreaRect)")

            // Create barrier window
            if !isHidden {
                let barrier = BarrierWindow(frame: result.reservedRect)
                barrier.orderFront(nil)
                barrierWindows[display.displayID] = barrier
                Log.info("  Barrier window created")
            }

            // Monitor and move bound app
            if let boundApp = layout.boundApp {
                Log.info("  Setting up bound app: \(boundApp.displayName) (\(boundApp.bundleIdentifier))")
                windowMonitor.monitorApp(bundleIdentifier: boundApp.bundleIdentifier)

                // Unhide the app first if it was hidden
                let apps = NSRunningApplication.runningApplications(withBundleIdentifier: boundApp.bundleIdentifier)
                Log.info("  Found \(apps.count) running instances")
                for app in apps {
                    if app.isHidden {
                        app.unhide()
                    }
                }

                // Delay slightly to allow unhide to take effect
                let targetRect = result.reservedRect
                let bundleID = boundApp.bundleIdentifier
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.moveBoundApp(bundleIdentifier: bundleID, to: targetRect)
                }
            }

            // Constrain existing windows
            if !isHidden {
                let workArea = result.workAreaRect
                let reservedArea = result.reservedRect
                let edge = layout.reservedArea.edge
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    self.constrainWindows(
                        workArea: workArea,
                        reservedArea: reservedArea,
                        edge: edge,
                        excludedBundleIDs: self.excludedBundleIDs()
                    )
                }
            }
        }
    }

    // MARK: - Visibility Toggle (⌘⌥M)

    func toggleVisibility() {
        isHidden.toggle()
        Log.info("toggleVisibility, isHidden=\(isHidden)")

        if isHidden {
            for (_, barrier) in barrierWindows {
                barrier.orderOut(nil)
            }
            for display in displayManager.displays {
                let layout = AppConfig.shared.layout(for: display.displayID)
                if let boundApp = layout.boundApp {
                    hideBoundApp(bundleIdentifier: boundApp.bundleIdentifier)
                }
            }
        } else {
            applyConfiguration()
        }
    }

    // MARK: - WindowMonitorDelegate

    func windowMonitorDidDetectChange(_ monitor: WindowMonitor) {
        guard !isHidden else { return }

        // Debounce: cancel previous timer and set a new one
        constrainDebounceTimer?.invalidate()
        constrainDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.handleWindowChange()
        }
    }

    private func handleWindowChange() {
        for display in displayManager.displays {
            let layout = AppConfig.shared.layout(for: display.displayID)
            guard layout.isActive else { continue }

            let result = LayoutEngine.calculate(
                screenFrame: display.visibleFrame,
                area: layout.reservedArea
            )

            // Constrain non-bound windows
            constrainWindows(
                workArea: result.workAreaRect,
                reservedArea: result.reservedRect,
                edge: layout.reservedArea.edge,
                excludedBundleIDs: excludedBundleIDs()
            )

            // Ensure bound app stays in reserved area
            if let boundApp = layout.boundApp {
                let axWindows = WindowController.windows(for: boundApp.bundleIdentifier)
                for window in axWindows {
                    guard WindowController.isMovable(window) else { continue }
                    guard let currentFrame = WindowController.getFrame(window) else { continue }
                    // Only move if the window has drifted away from the reserved rect
                    if !rectsApproximatelyEqual(currentFrame, result.reservedRect, tolerance: 5) {
                        WindowController.setFrame(window, to: result.reservedRect)
                    }
                }
            }
        }
    }

    // MARK: - DisplayManagerDelegate

    func displayManagerDidDetectChange(_ manager: DisplayManager) {
        Log.info("Display configuration changed, re-applying")
        applyConfiguration()
    }

    // MARK: - Private Helpers

    private func moveBoundApp(bundleIdentifier: String, to rect: CGRect) {
        let axWindows = WindowController.windows(for: bundleIdentifier)
        Log.info("moveBoundApp '\(bundleIdentifier)' found \(axWindows.count) AX windows, target=\(rect)")

        if axWindows.isEmpty {
            Log.info("  No AX windows found — app may not have windows yet or AX permission missing")
        }

        for (index, window) in axWindows.enumerated() {
            let role = WindowController.getRole(window) ?? "nil"
            let subrole = WindowController.getSubrole(window) ?? "nil"
            let movable = WindowController.isMovable(window)
            let frame = WindowController.getFrame(window)
            Log.info("  window[\(index)] role=\(role) subrole=\(subrole) movable=\(movable) frame=\(String(describing: frame))")

            guard movable else {
                Log.info("  window[\(index)] skipped — not movable")
                continue
            }
            WindowController.setFrame(window, to: rect)
            // Verify
            if let newFrame = WindowController.getFrame(window) {
                Log.info("  window[\(index)] after setFrame: \(newFrame)")
            }
        }
    }

    private func hideBoundApp(bundleIdentifier: String) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        for app in apps {
            app.hide()
        }
    }

    private func constrainWindows(workArea: CGRect, reservedArea: CGRect, edge: EdgePosition, excludedBundleIDs: Set<String>) {
        WorkAreaConstraint.constrainAllWindows(
            workArea: workArea,
            reservedArea: reservedArea,
            edge: edge,
            excludedBundleIDs: excludedBundleIDs,
            ownBundleID: ownBundleID
        )
    }

    private func excludedBundleIDs() -> Set<String> {
        var excluded: Set<String> = [ownBundleID]
        for display in displayManager.displays {
            let layout = AppConfig.shared.layout(for: display.displayID)
            if let bundleID = layout.boundApp?.bundleIdentifier {
                excluded.insert(bundleID)
            }
        }
        return excluded
    }

    private func removeAllBarrierWindows() {
        for (_, barrier) in barrierWindows {
            barrier.orderOut(nil)
        }
        barrierWindows.removeAll()
    }

    private func rectsApproximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        return abs(a.origin.x - b.origin.x) < tolerance &&
               abs(a.origin.y - b.origin.y) < tolerance &&
               abs(a.width - b.width) < tolerance &&
               abs(a.height - b.height) < tolerance
    }
}
