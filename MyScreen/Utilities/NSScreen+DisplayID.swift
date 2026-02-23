import AppKit
import CoreGraphics

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? CGMainDisplayID()
    }

    /// Returns the screen frame in CG coordinates (top-left origin).
    /// Note: NSScreen.screens.first is always the primary display per Apple docs.
    var cgFrame: CGRect {
        guard let mainScreen = NSScreen.screens.first else {
            Log.info("NSScreen.screens is empty in cgFrame")
            return frame
        }
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
        guard let mainScreen = NSScreen.screens.first else {
            Log.info("NSScreen.screens is empty in cgVisibleFrame")
            return visibleFrame
        }
        let mainHeight = mainScreen.frame.height
        return CGRect(
            x: visibleFrame.origin.x,
            y: mainHeight - visibleFrame.origin.y - visibleFrame.height,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
    }
}
