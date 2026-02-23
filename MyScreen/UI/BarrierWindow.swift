import AppKit

/// A transparent, click-through window that sits at `.floating` level
/// to protect the reserved area from being covered by other windows.
final class BarrierWindow: NSWindow {
    init(frame: CGRect) {
        // Convert CG rect (top-left origin) to NS rect (bottom-left origin) for NSWindow
        let nsRect = Self.cgToNS(frame)
        super.init(
            contentRect: nsRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Draw a subtle divider line
        let dividerView = DividerView(frame: NSRect(origin: .zero, size: nsRect.size))
        contentView = dividerView
    }

    func updateFrame(cgRect: CGRect) {
        let nsRect = Self.cgToNS(cgRect)
        setFrame(nsRect, display: true)
        contentView?.frame = NSRect(origin: .zero, size: nsRect.size)
        if let divider = contentView as? DividerView {
            divider.needsDisplay = true
        }
    }

    private static func cgToNS(_ cgRect: CGRect) -> NSRect {
        guard let mainScreen = NSScreen.screens.first else { return cgRect }
        let mainHeight = mainScreen.frame.height
        return NSRect(
            x: cgRect.origin.x,
            y: mainHeight - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )
    }
}

/// Draws a 1px divider line along the edge adjacent to the work area.
private final class DividerView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.withAlphaComponent(0.3).setFill()

        // Draw a thin line along the left edge (common for right-side reserved area)
        // The ScreenManager will position the window exactly on the reserved area,
        // so the left edge is adjacent to the work area for right-side config.
        // We draw lines on all edges; only the visible one matters.
        let lineWidth: CGFloat = 1

        // Left edge
        NSRect(x: 0, y: 0, width: lineWidth, height: bounds.height).fill()
        // Right edge
        NSRect(x: bounds.width - lineWidth, y: 0, width: lineWidth, height: bounds.height).fill()
        // Top edge
        NSRect(x: 0, y: bounds.height - lineWidth, width: bounds.width, height: lineWidth).fill()
        // Bottom edge
        NSRect(x: 0, y: 0, width: bounds.width, height: lineWidth).fill()
    }
}
