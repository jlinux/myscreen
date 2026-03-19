import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var screenManager: ScreenManager?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("App launched, bundleID=\(Bundle.main.bundleIdentifier ?? "nil")")
        NSApp.setActivationPolicy(.accessory)

        statusBarController = StatusBarController()

        checkAndRequestPermission()
    }

    private func checkAndRequestPermission() {
        let trusted = AccessibilityHelper.isTrusted()
        Log.info("Accessibility trusted=\(trusted)")

        if trusted {
            activateScreenManager()
        } else {
            // Trigger system permission dialog
            AccessibilityHelper.requestAccess()
            Log.info("Requested accessibility access, polling for grant...")

            // Poll every second
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                if AccessibilityHelper.isTrusted() {
                    timer.invalidate()
                    self?.permissionTimer = nil
                    Log.info("Permission granted!")
                    self?.activateScreenManager()
                }
            }
        }
    }

    private func activateScreenManager() {
        screenManager = ScreenManager()
        screenManager?.start()
        statusBarController?.bindScreenManager(screenManager!)
        Log.info("ScreenManager activated and bound to StatusBar")
    }
}

/// Simple stderr logger — always visible in Console and terminal.
enum Log {
    static func info(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] MyScreen: \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
