import AppKit
import ApplicationServices

enum AccessibilityHelper {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Polls until accessibility is granted, then calls the completion on the main thread.
    /// Returns the polling Timer so the caller can invalidate it if needed.
    @discardableResult
    static func waitForTrust(pollInterval: TimeInterval = 1.0, completion: @escaping () -> Void) -> Timer? {
        if isTrusted() {
            DispatchQueue.main.async { completion() }
            return nil
        }
        requestAccess()
        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { timer in
            if isTrusted() {
                timer.invalidate()
                DispatchQueue.main.async { completion() }
            }
        }
        return timer
    }
}
