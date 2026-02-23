import AppKit
import ApplicationServices

/// AXUIElement wrapper for controlling other application windows.
enum WindowController {
    /// Get all AXUIElement windows for a given PID.
    static func windows(for pid: pid_t) -> [AXUIElement] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            return []
        }
        return windows
    }

    /// Get all windows for a bundle identifier.
    static func windows(for bundleIdentifier: String) -> [AXUIElement] {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        return apps.flatMap { windows(for: $0.processIdentifier) }
    }

    /// Get the position of a window (CG coordinates, top-left origin).
    static func getPosition(_ window: AXUIElement) -> CGPoint? {
        var positionRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)
        guard result == .success else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &point)
        return point
    }

    /// Get the size of a window.
    static func getSize(_ window: AXUIElement) -> CGSize? {
        var sizeRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        guard result == .success else { return nil }
        var size = CGSize.zero
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return size
    }

    /// Get the frame of a window (CG coordinates).
    static func getFrame(_ window: AXUIElement) -> CGRect? {
        guard let position = getPosition(window), let size = getSize(window) else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Set the position of a window (CG coordinates, top-left origin).
    static func setPosition(_ window: AXUIElement, to point: CGPoint) {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    /// Set the size of a window.
    static func setSize(_ window: AXUIElement, to size: CGSize) {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    /// Move and resize a window to a target frame.
    /// Uses set-size → set-position → set-size pattern for reliable cross-display moves.
    static func setFrame(_ window: AXUIElement, to frame: CGRect) {
        setSize(window, to: frame.size)
        setPosition(window, to: frame.origin)
        setSize(window, to: frame.size)
    }

    /// Get the PID that owns a window.
    static func ownerPID(of window: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(window, &pid)
        return result == .success ? pid : nil
    }

    /// Check if a window is a standard, resizable window (not a dialog or sheet).
    static func isStandardWindow(_ window: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleRef)
        guard result == .success, let role = roleRef as? String else { return false }
        return role == kAXWindowRole
    }

    /// Check if a window has the standard close/minimize/zoom buttons (indicating it's a real window).
    static func isResizable(_ window: AXUIElement) -> Bool {
        var subroleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef)
        guard result == .success, let subrole = subroleRef as? String else { return false }
        return subrole == kAXStandardWindowSubrole
    }
}
