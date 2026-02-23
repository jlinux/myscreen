import CoreGraphics
import AppKit

struct WindowInfo {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let bundleIdentifier: String?
    let frame: CGRect  // CG coordinates (top-left origin)
    let layer: Int
    let isOnScreen: Bool
}

enum CGWindowListHelper {
    static func allWindows() -> [WindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else {
            return []
        }

        return windowList.compactMap { dict -> WindowInfo? in
            guard let windowID = dict[kCGWindowNumber] as? CGWindowID,
                  let ownerPID = dict[kCGWindowOwnerPID] as? pid_t,
                  let ownerName = dict[kCGWindowOwnerName] as? String,
                  let boundsDict = dict[kCGWindowBounds] as? [String: CGFloat],
                  let layer = dict[kCGWindowLayer] as? Int else {
                return nil
            }

            // Normal windows are at layer 0
            guard layer == 0 else { return nil }

            let frame = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            let isOnScreen = dict[kCGWindowIsOnscreen] as? Bool ?? false

            // Try to get bundle identifier from PID
            let bundleID = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier

            return WindowInfo(
                windowID: windowID,
                ownerPID: ownerPID,
                ownerName: ownerName,
                bundleIdentifier: bundleID,
                frame: frame,
                layer: layer,
                isOnScreen: isOnScreen
            )
        }
    }

    static func windows(for bundleIdentifier: String) -> [WindowInfo] {
        allWindows().filter { $0.bundleIdentifier == bundleIdentifier }
    }
}
