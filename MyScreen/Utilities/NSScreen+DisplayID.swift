import AppKit
import CoreGraphics

enum CoordinateConverter {
    private static var mainScreenHeight: CGFloat? {
        NSScreen.screens.first?.frame.height
    }

    static func nsToCG(_ rect: CGRect) -> CGRect {
        guard let mainScreenHeight else { return rect }
        return CGRect(
            x: rect.origin.x,
            y: mainScreenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    static func cgToNS(_ rect: CGRect) -> CGRect {
        guard let mainScreenHeight else { return rect }
        return CGRect(
            x: rect.origin.x,
            y: mainScreenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? CGMainDisplayID()
    }

    /// Returns the screen frame in CG coordinates (top-left origin).
    /// Note: NSScreen.screens.first is always the primary display per Apple docs.
    var cgFrame: CGRect {
        CoordinateConverter.nsToCG(frame)
    }

    /// Visible frame (excluding menu bar and dock) in CG coordinates.
    var cgVisibleFrame: CGRect {
        CoordinateConverter.nsToCG(visibleFrame)
    }
}
