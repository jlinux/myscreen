import CoreGraphics
import AppKit

/// Checks if windows intrude into reserved areas and clips them.
enum WorkAreaConstraint {
    private static func windowBelongsToDisplay(_ windowFrame: CGRect, displayFrame: CGRect) -> Bool {
        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        return displayFrame.contains(center)
    }

    /// Constrain a window frame to stay within the work area.
    /// Clamps the whole frame into the work area. Returns nil if no adjustment needed.
    static func constrainedFrame(
        windowFrame: CGRect,
        workArea: CGRect,
        reservedAreas: [(rect: CGRect, edge: EdgePosition)]
    ) -> CGRect? {
        let intrudesReservedArea = reservedAreas.contains { reservedRect, _ in
            windowFrame.intersects(reservedRect)
        }
        let exceedsWorkArea = !workArea.contains(windowFrame)
        guard intrudesReservedArea || exceedsWorkArea else { return nil }

        let minWidth = min(CGFloat(100), workArea.width)
        let minHeight = min(CGFloat(100), workArea.height)

        let clampedWidth = min(max(windowFrame.width, minWidth), workArea.width)
        let clampedHeight = min(max(windowFrame.height, minHeight), workArea.height)
        let clampedX = min(max(windowFrame.origin.x, workArea.minX), workArea.maxX - clampedWidth)
        let clampedY = min(max(windowFrame.origin.y, workArea.minY), workArea.maxY - clampedHeight)

        let newFrame = CGRect(x: clampedX, y: clampedY, width: clampedWidth, height: clampedHeight)
        return newFrame == windowFrame ? nil : newFrame
    }

    /// Constrain all on-screen windows to the work area.
    static func constrainAllWindows(
        displayFrame: CGRect,
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
            guard windowBelongsToDisplay(windowInfo.frame, displayFrame: displayFrame) else { continue }

            // Skip small windows (popups, tooltips, input method candidates, etc.)
            if windowInfo.frame.width < 150 || windowInfo.frame.height < 100 { continue }

            guard let newFrame = constrainedFrame(
                windowFrame: windowInfo.frame,
                workArea: workArea,
                reservedAreas: reservedAreas
            ) else { continue }

            let axWindows = WindowController.windows(for: windowInfo.ownerPID)
            for axWindow in axWindows {
                guard WindowController.isMainWindow(axWindow),
                      let frame = WindowController.getFrame(axWindow) else { continue }
                if abs(frame.origin.x - windowInfo.frame.origin.x) < 5 &&
                   abs(frame.origin.y - windowInfo.frame.origin.y) < 5 {
                    WindowController.setFrame(axWindow, to: newFrame)
                    break
                }
            }
        }
    }
}
