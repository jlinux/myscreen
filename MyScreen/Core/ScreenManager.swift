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

    func start() {
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
        removeAllBarrierWindows()

        for display in displayManager.displays {
            let layout = AppConfig.shared.layout(for: display.displayID)
            guard layout.isActive else { continue }

            let result = LayoutEngine.calculate(
                screenFrame: display.visibleFrame,
                area: layout.reservedArea
            )

            // Create barrier window
            if !isHidden {
                let barrier = BarrierWindow(frame: result.reservedRect)
                barrier.orderFront(nil)
                barrierWindows[display.displayID] = barrier
            }

            // Monitor bound app
            if let boundApp = layout.boundApp {
                windowMonitor.monitorApp(bundleIdentifier: boundApp.bundleIdentifier)
                moveBoundApp(bundleIdentifier: boundApp.bundleIdentifier, to: result.reservedRect)
            }

            // Constrain existing windows
            if !isHidden {
                constrainWindows(
                    workArea: result.workAreaRect,
                    reservedArea: result.reservedRect,
                    edge: layout.reservedArea.edge,
                    excludedBundleIDs: excludedBundleIDs()
                )
            }
        }
    }

    // MARK: - Visibility Toggle (⌘⌥M)

    func toggleVisibility() {
        isHidden.toggle()

        if isHidden {
            // Hide all barrier windows and let work area expand
            for (_, barrier) in barrierWindows {
                barrier.orderOut(nil)
            }
            // Hide bound app windows
            for display in displayManager.displays {
                let layout = AppConfig.shared.layout(for: display.displayID)
                if let boundApp = layout.boundApp {
                    hideBoundApp(bundleIdentifier: boundApp.bundleIdentifier)
                }
            }
        } else {
            // Show barrier windows and re-constrain
            applyConfiguration()
        }
    }

    // MARK: - WindowMonitorDelegate

    func windowMonitorDidDetectChange(_ monitor: WindowMonitor) {
        guard !isHidden else { return }

        for display in displayManager.displays {
            let layout = AppConfig.shared.layout(for: display.displayID)
            guard layout.isActive else { continue }

            let result = LayoutEngine.calculate(
                screenFrame: display.visibleFrame,
                area: layout.reservedArea
            )

            // Re-constrain windows
            constrainWindows(
                workArea: result.workAreaRect,
                reservedArea: result.reservedRect,
                edge: layout.reservedArea.edge,
                excludedBundleIDs: excludedBundleIDs()
            )

            // Ensure bound app stays in reserved area
            if let boundApp = layout.boundApp {
                moveBoundApp(bundleIdentifier: boundApp.bundleIdentifier, to: result.reservedRect)
            }
        }
    }

    // MARK: - DisplayManagerDelegate

    func displayManagerDidDetectChange(_ manager: DisplayManager) {
        applyConfiguration()
    }

    // MARK: - Private Helpers

    private func moveBoundApp(bundleIdentifier: String, to rect: CGRect) {
        let axWindows = WindowController.windows(for: bundleIdentifier)
        for window in axWindows {
            guard WindowController.isStandardWindow(window) else { continue }
            WindowController.setFrame(window, to: rect)
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
}
