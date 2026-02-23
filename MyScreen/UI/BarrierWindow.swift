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

        let dividerView = DividerView(frame: NSRect(origin: .zero, size: nsRect.size))
        contentView = dividerView

        NSLog("MyScreen: BarrierWindow created at NS frame (%.0f, %.0f, %.0f, %.0f)",
              nsRect.origin.x, nsRect.origin.y, nsRect.width, nsRect.height)
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

/// Draws a semi-transparent background with a divider line.
private final class DividerView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        // Semi-transparent background so the user can see the reserved area
        NSColor.controlBackgroundColor.withAlphaComponent(0.05).setFill()
        bounds.fill()

        // Draw visible divider lines
        NSColor.separatorColor.withAlphaComponent(0.5).setFill()
        let lineWidth: CGFloat = 2

        // All edges
        NSRect(x: 0, y: 0, width: lineWidth, height: bounds.height).fill()
        NSRect(x: bounds.width - lineWidth, y: 0, width: lineWidth, height: bounds.height).fill()
        NSRect(x: 0, y: bounds.height - lineWidth, width: bounds.width, height: lineWidth).fill()
        NSRect(x: 0, y: 0, width: bounds.width, height: lineWidth).fill()
    }
}
