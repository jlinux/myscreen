import AppKit
import ApplicationServices

/// AXUIElement wrapper for controlling other application windows.
enum WindowController {
    struct BindableWindowInfo: Identifiable, Equatable {
        let id: String
        let title: String
        let identifier: String?
        let subrole: String?
        let frame: CGRect
    }

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

    /// Get the title of a window.
    static func getTitle(_ window: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        guard result == .success else { return nil }
        let title = (titleRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (title?.isEmpty == false) ? title : nil
    }

    /// Get the AX identifier of a window if exposed by the target app.
    static func getIdentifier(_ window: AXUIElement) -> String? {
        var identifierRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, "AXIdentifier" as CFString, &identifierRef)
        guard result == .success else { return nil }
        let identifier = (identifierRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (identifier?.isEmpty == false) ? identifier : nil
    }

    /// Check if a window is in full-screen mode.
    static func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value)
        guard result == .success else { return false }
        return (value as? Bool) == true
    }

    static func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value)
        guard result == .success else { return false }
        return (value as? Bool) == true
    }

    @discardableResult
    static func setMinimized(_ window: AXUIElement, to minimized: Bool) -> Bool {
        let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, minimized as CFBoolean)
        if result != .success {
            NSLog("MyScreen: setMinimized failed, error=%d", result.rawValue)
        }
        return result == .success
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

    static func bindableWindows(for bundleIdentifier: String) -> [BindableWindowInfo] {
        windows(for: bundleIdentifier)
            .compactMap { window -> BindableWindowInfo? in
                guard isMovable(window),
                      isMainWindow(window),
                      let frame = getFrame(window) else { return nil }

                let title = getTitle(window) ?? "Untitled Window"
                let identifier = getIdentifier(window)
                let subrole = getSubrole(window)
                let id = [
                    identifier ?? "",
                    title,
                    subrole ?? "",
                    String(Int(frame.origin.x)),
                    String(Int(frame.origin.y)),
                    String(Int(frame.width)),
                    String(Int(frame.height)),
                ].joined(separator: "|")

                return BindableWindowInfo(
                    id: id,
                    title: title,
                    identifier: identifier,
                    subrole: subrole,
                    frame: frame
                )
            }
            .sorted {
                if $0.title != $1.title {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.frame.origin.x < $1.frame.origin.x
            }
    }

    static func bestWindow(for binding: AppBinding) -> AXUIElement? {
        let candidates = windows(for: binding.bundleIdentifier).compactMap { window -> WindowCandidate? in
            guard isMovable(window),
                  isMainWindow(window),
                  let frame = getFrame(window) else { return nil }

            return WindowCandidate(
                window: window,
                title: getTitle(window),
                identifier: getIdentifier(window),
                subrole: getSubrole(window),
                frame: frame
            )
        }

        guard !candidates.isEmpty else { return nil }

        if let identifier = binding.windowIdentifier,
           let exactIdentifier = candidates.first(where: { $0.identifier == identifier }) {
            return exactIdentifier.window
        }

        if let title = normalized(binding.windowTitle) {
            let exactTitleMatches = candidates.filter { normalized($0.title) == title }
            if let match = nearestCandidate(to: binding, in: exactTitleMatches) {
                return match.window
            }
        }

        if let subrole = binding.windowSubrole {
            let subroleMatches = candidates.filter { $0.subrole == subrole }
            if let match = nearestCandidate(to: binding, in: subroleMatches) {
                return match.window
            }
        }

        return nearestCandidate(to: binding, in: candidates)?.window
    }

    private struct WindowCandidate {
        let window: AXUIElement
        let title: String?
        let identifier: String?
        let subrole: String?
        let frame: CGRect
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized.lowercased()
    }

    private static func nearestCandidate(to binding: AppBinding, in candidates: [WindowCandidate]) -> WindowCandidate? {
        guard !candidates.isEmpty else { return nil }

        if let title = normalized(binding.windowTitle) {
            let titled = candidates.filter { normalized($0.title) == title }
            if !titled.isEmpty {
                return titled.min { compareCandidates($0, $1, binding: binding) }
            }
        }

        return candidates.min { compareCandidates($0, $1, binding: binding) }
    }

    private static func compareCandidates(_ lhs: WindowCandidate, _ rhs: WindowCandidate, binding: AppBinding) -> Bool {
        let lhsScore = frameDistanceScore(lhs.frame, binding: binding)
        let rhsScore = frameDistanceScore(rhs.frame, binding: binding)
        if lhsScore != rhsScore {
            return lhsScore < rhsScore
        }

        if lhs.frame.origin.y != rhs.frame.origin.y {
            return lhs.frame.origin.y < rhs.frame.origin.y
        }
        if lhs.frame.origin.x != rhs.frame.origin.x {
            return lhs.frame.origin.x < rhs.frame.origin.x
        }
        if lhs.frame.width != rhs.frame.width {
            return lhs.frame.width < rhs.frame.width
        }
        return lhs.frame.height < rhs.frame.height
    }

    private static func frameDistanceScore(_ frame: CGRect, binding: AppBinding) -> CGFloat {
        guard let target = binding.lastKnownFrame?.cgRect else { return 0 }
        let dx = frame.midX - target.midX
        let dy = frame.midY - target.midY
        let dw = frame.width - target.width
        let dh = frame.height - target.height
        return abs(dx) + abs(dy) + abs(dw) + abs(dh)
    }
}
