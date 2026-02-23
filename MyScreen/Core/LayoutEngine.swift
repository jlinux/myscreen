import CoreGraphics

/// Pure geometry calculations — no side effects.
/// All coordinates use CG system (top-left origin).
struct LayoutResult {
    let reservedRect: CGRect
    let workAreaRect: CGRect
    /// Thin strip rect along the divider edge for the barrier window (drag handle).
    let dividerRect: CGRect
}

enum LayoutEngine {
    /// Calculate reserved area and work area rects from a screen frame and configuration.
    /// - Parameters:
    ///   - screenFrame: The full screen frame in CG coordinates (top-left origin)
    ///   - area: The reserved area configuration
    /// - Returns: The reserved rect and work area rect
    static func calculate(screenFrame: CGRect, area: ReservedArea) -> LayoutResult {
        let totalWidth = screenFrame.width
        let totalHeight = screenFrame.height
        let originX = screenFrame.origin.x
        let originY = screenFrame.origin.y

        let reservedRect: CGRect
        let workAreaRect: CGRect

        switch area.edge {
        case .left:
            let w = area.size.resolve(for: totalWidth)
            reservedRect = CGRect(x: originX, y: originY, width: w, height: totalHeight)
            workAreaRect = CGRect(x: originX + w, y: originY, width: totalWidth - w, height: totalHeight)

        case .right:
            let w = area.size.resolve(for: totalWidth)
            reservedRect = CGRect(x: originX + totalWidth - w, y: originY, width: w, height: totalHeight)
            workAreaRect = CGRect(x: originX, y: originY, width: totalWidth - w, height: totalHeight)

        case .top:
            let h = area.size.resolve(for: totalHeight)
            reservedRect = CGRect(x: originX, y: originY, width: totalWidth, height: h)
            workAreaRect = CGRect(x: originX, y: originY + h, width: totalWidth, height: totalHeight - h)

        case .bottom:
            let h = area.size.resolve(for: totalHeight)
            reservedRect = CGRect(x: originX, y: originY + totalHeight - h, width: totalWidth, height: h)
            workAreaRect = CGRect(x: originX, y: originY, width: totalWidth, height: totalHeight - h)
        }

        let dividerWidth: CGFloat = 8
        let dividerRect: CGRect
        switch area.edge {
        case .left:
            dividerRect = CGRect(x: reservedRect.maxX - dividerWidth, y: reservedRect.origin.y, width: dividerWidth, height: reservedRect.height)
        case .right:
            dividerRect = CGRect(x: reservedRect.origin.x, y: reservedRect.origin.y, width: dividerWidth, height: reservedRect.height)
        case .top:
            dividerRect = CGRect(x: reservedRect.origin.x, y: reservedRect.maxY - dividerWidth, width: reservedRect.width, height: dividerWidth)
        case .bottom:
            dividerRect = CGRect(x: reservedRect.origin.x, y: reservedRect.origin.y, width: reservedRect.width, height: dividerWidth)
        }

        return LayoutResult(reservedRect: reservedRect, workAreaRect: workAreaRect, dividerRect: dividerRect)
    }
}
