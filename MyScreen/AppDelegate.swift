import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var screenManager: ScreenManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()

        if AccessibilityHelper.isTrusted() {
            activateScreenManager()
        } else {
            statusBarController?.showPermissionGuide {
                self.activateScreenManager()
            }
        }
    }

    private func activateScreenManager() {
        screenManager = ScreenManager()
        screenManager?.start()
        statusBarController?.bindScreenManager(screenManager!)
    }
}
