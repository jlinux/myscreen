import CoreGraphics
import AppKit

/// Checks if windows intrude into reserved areas and clips them.
enum WorkAreaConstraint {
    /// Calculate the constrained frame for a window that intrudes into the reserved area.
    /// Returns nil if the window doesn't intrude (no adjustment needed).
    /// Only clips the overlapping edge — does not move the window.
    static func constrainedFrame(
        windowFrame: CGRect,
        workArea: CGRect,
        reservedArea: CGRect,
        edge: EdgePosition
    ) -> CGRect? {
        // Check if the window actually overlaps with the reserved area
        guard windowFrame.intersects(reservedArea) else { return nil }

        var newFrame = windowFrame

        switch edge {
        case .right:
            // Reserved area is on the right — clip window's right edge
            let maxX = workArea.maxX
            if newFrame.maxX > maxX {
                newFrame.size.width = maxX - newFrame.origin.x
            }

        case .left:
            // Reserved area is on the left — clip window's left edge
            let minX = workArea.minX
            if newFrame.origin.x < minX {
                let overflow = minX - newFrame.origin.x
                newFrame.origin.x = minX
                newFrame.size.width -= overflow
            }

        case .bottom:
            // Reserved area is on the bottom — clip window's bottom edge
            let maxY = workArea.maxY
            if newFrame.maxY > maxY {
                newFrame.size.height = maxY - newFrame.origin.y
            }

        case .top:
            // Reserved area is on the top — clip window's top edge
            let minY = workArea.minY
            if newFrame.origin.y < minY {
                let overflow = minY - newFrame.origin.y
                newFrame.origin.y = minY
                newFrame.size.height -= overflow
            }
        }

        // Ensure minimum size
        newFrame.size.width = max(newFrame.size.width, 100)
        newFrame.size.height = max(newFrame.size.height, 100)

        // Only return if the frame actually changed
        if newFrame == windowFrame { return nil }
        return newFrame
    }

    /// Constrain all on-screen windows to a work area, excluding specified bundle IDs.
    static func constrainAllWindows(
        workArea: CGRect,
        reservedArea: CGRect,
        edge: EdgePosition,
        excludedBundleIDs: Set<String>,
        ownBundleID: String
    ) {
        let windows = CGWindowListHelper.allWindows()

        for windowInfo in windows {
            // Skip excluded apps and our own windows
            if let bundleID = windowInfo.bundleIdentifier {
                if excludedBundleIDs.contains(bundleID) || bundleID == ownBundleID {
                    continue
                }
            }

            guard windowInfo.isOnScreen else { continue }

            // Check if this window needs constraining
            guard let newFrame = constrainedFrame(
                windowFrame: windowInfo.frame,
                workArea: workArea,
                reservedArea: reservedArea,
                edge: edge
            ) else { continue }

            // Use AXUIElement to resize the window
            let axWindows = WindowController.windows(for: windowInfo.ownerPID)
            for axWindow in axWindows {
                guard let frame = WindowController.getFrame(axWindow) else { continue }
                // Match by position (approximately)
                if abs(frame.origin.x - windowInfo.frame.origin.x) < 5 &&
                   abs(frame.origin.y - windowInfo.frame.origin.y) < 5 {
                    WindowController.setFrame(axWindow, to: newFrame)
                    break
                }
            }
        }
    }
}
