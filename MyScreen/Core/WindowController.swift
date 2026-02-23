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
            NSLog("MyScreen: AX windows query failed for PID %d, error=%d", pid, result.rawValue)
            return []
        }
        return windows
    }

    /// Get all windows for a bundle identifier.
    static func windows(for bundleIdentifier: String) -> [AXUIElement] {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        if apps.isEmpty {
            NSLog("MyScreen: No running apps found for bundleID=%@", bundleIdentifier)
        }
        return apps.flatMap { windows(for: $0.processIdentifier) }
    }

    /// Get the position of a window (CG coordinates, top-left origin).
    static func getPosition(_ window: AXUIElement) -> CGPoint? {
        var positionRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)
        guard result == .success, let ref = positionRef else { return nil }
        guard CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        // swiftlint:disable:next force_cast
        AXValueGetValue(ref as! AXValue, .cgPoint, &point)
        return point
    }

    /// Get the size of a window.
    static func getSize(_ window: AXUIElement) -> CGSize? {
        var sizeRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        guard result == .success, let ref = sizeRef else { return nil }
        guard CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        AXValueGetValue(ref as! AXValue, .cgSize, &size)
        return size
    }

    /// Get the frame of a window (CG coordinates).
    static func getFrame(_ window: AXUIElement) -> CGRect? {
        guard let position = getPosition(window), let size = getSize(window) else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Set the position of a window (CG coordinates, top-left origin).
    @discardableResult
    static func setPosition(_ window: AXUIElement, to point: CGPoint) -> Bool {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return false }
        let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        if result != .success {
            NSLog("MyScreen: setPosition failed, error=%d", result.rawValue)
        }
        return result == .success
    }

    /// Set the size of a window.
    @discardableResult
    static func setSize(_ window: AXUIElement, to size: CGSize) -> Bool {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return false }
        let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        if result != .success {
            NSLog("MyScreen: setSize failed, error=%d", result.rawValue)
        }
        return result == .success
    }

    /// Move and resize a window to a target frame.
    /// Uses set-size → set-position → set-size pattern for reliable cross-display moves.
    static func setFrame(_ window: AXUIElement, to frame: CGRect) {
        NSLog("MyScreen: setFrame to (%.0f, %.0f, %.0f, %.0f)",
              frame.origin.x, frame.origin.y, frame.width, frame.height)
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

    /// Get the role of a window.
    static func getRole(_ window: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleRef)
        guard result == .success else { return nil }
        return roleRef as? String
    }

    /// Get the subrole of a window.
    static func getSubrole(_ window: AXUIElement) -> String? {
        var subroleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef)
        guard result == .success else { return nil }
        return subroleRef as? String
    }

    /// Check if a window is movable (has position + size attributes).
    static func isMovable(_ window: AXUIElement) -> Bool {
        return getPosition(window) != nil && getSize(window) != nil
    }

    /// Check if a window is a main/standard window (not a popup, dialog, or helper).
    /// Returns true for AXWindow role. Skips menus, popovers, sheets, etc.
    static func isMainWindow(_ window: AXUIElement) -> Bool {
        guard let role = getRole(window), role == "AXWindow" else { return false }
        // Allow standard windows and dialogs, skip floating/system windows
        let subrole = getSubrole(window)
        // nil subrole is OK (some apps don't set it)
        if let subrole = subrole {
            let allowedSubroles: Set<String> = ["AXStandardWindow", "AXDialog"]
            return allowedSubroles.contains(subrole)
        }
        return true
    }
}
