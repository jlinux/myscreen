import CoreGraphics
import AppKit

/// Checks if windows intrude into reserved areas and clips them.
enum WorkAreaConstraint {
    /// Constrain a window frame to stay within the work area.
    /// Clips from each reserved area edge. Returns nil if no adjustment needed.
    static func constrainedFrame(
        windowFrame: CGRect,
        workArea: CGRect,
        reservedAreas: [(rect: CGRect, edge: EdgePosition)]
    ) -> CGRect? {
        var newFrame = windowFrame
        var changed = false

        for (reservedRect, edge) in reservedAreas {
            guard newFrame.intersects(reservedRect) else { continue }

            switch edge {
            case .right:
                let maxX = workArea.maxX
                if newFrame.maxX > maxX {
                    newFrame.size.width = maxX - newFrame.origin.x
                    changed = true
                }
            case .left:
                let minX = workArea.minX
                if newFrame.origin.x < minX {
                    let overflow = minX - newFrame.origin.x
                    newFrame.origin.x = minX
                    newFrame.size.width -= overflow
                    changed = true
                }
            case .bottom:
                let maxY = workArea.maxY
                if newFrame.maxY > maxY {
                    newFrame.size.height = maxY - newFrame.origin.y
                    changed = true
                }
            case .top:
                let minY = workArea.minY
                if newFrame.origin.y < minY {
                    let overflow = minY - newFrame.origin.y
                    newFrame.origin.y = minY
                    newFrame.size.height -= overflow
                    changed = true
                }
            }
        }

        guard changed else { return nil }

        // Ensure minimum size
        newFrame.size.width = max(newFrame.size.width, 100)
        newFrame.size.height = max(newFrame.size.height, 100)

        if newFrame == windowFrame { return nil }
        return newFrame
    }

    /// Constrain all on-screen windows to the work area.
    static func constrainAllWindows(
        workArea: CGRect,
        reservedAreas: [(rect: CGRect, edge: EdgePosition)],
        excludedBundleIDs: Set<String>,
        ownBundleID: String
    ) {
        let windows = CGWindowListHelper.allWindows()

        for windowInfo in windows {
            if let bundleID = windowInfo.bundleIdentifier {
                if excludedBundleIDs.contains(bundleID) || bundleID == ownBundleID {
                    continue
                }
            }

            guard windowInfo.isOnScreen else { continue }

            guard let newFrame = constrainedFrame(
                windowFrame: windowInfo.frame,
                workArea: workArea,
                reservedAreas: reservedAreas
            ) else { continue }

            let axWindows = WindowController.windows(for: windowInfo.ownerPID)
            for axWindow in axWindows {
                guard let frame = WindowController.getFrame(axWindow) else { continue }
                if abs(frame.origin.x - windowInfo.frame.origin.x) < 5 &&
                   abs(frame.origin.y - windowInfo.frame.origin.y) < 5 {
                    WindowController.setFrame(axWindow, to: newFrame)
                    break
                }
            }
        }
    }
}
