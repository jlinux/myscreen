import AppKit
import CoreGraphics

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? CGMainDisplayID()
    }

    /// Returns the screen frame in CG coordinates (top-left origin).
    var cgFrame: CGRect {
        // NSScreen.frame uses bottom-left origin. The main screen's origin is (0, 0) in NS coords.
        // In CG coords the main screen origin is (0, 0) at top-left.
        guard let mainScreen = NSScreen.screens.first else { return frame }
        let mainHeight = mainScreen.frame.height
        return CGRect(
            x: frame.origin.x,
            y: mainHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    /// Visible frame (excluding menu bar and dock) in CG coordinates.
    var cgVisibleFrame: CGRect {
        guard let mainScreen = NSScreen.screens.first else { return visibleFrame }
        let mainHeight = mainScreen.frame.height
        return CGRect(
            x: visibleFrame.origin.x,
            y: mainHeight - visibleFrame.origin.y - visibleFrame.height,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
    }
}
