import AppKit

protocol BarrierWindowDelegate: AnyObject {
    func barrierWindow(_ window: BarrierWindow, didDragToSize newSize: CGFloat)
}

final class BarrierWindow: NSWindow {
    weak var resizeDelegate: BarrierWindowDelegate?
    var edge: EdgePosition = .right
    /// The actual reserved area size (not the divider strip size).
    var reservedAreaSize: CGFloat = 0
    /// The slot UUID this barrier window belongs to.
    var slotID: UUID?

    init(frame: CGRect, edge: EdgePosition = .right) {
        let nsRect = Self.cgToNS(frame)
        super.init(
            contentRect: nsRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        self.edge = edge
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        let dividerView = DividerView(frame: NSRect(origin: .zero, size: nsRect.size))
        dividerView.edge = edge
        dividerView.barrierWindow = self
        contentView = dividerView
    }

    func updateFrame(cgRect: CGRect) {
        let nsRect = Self.cgToNS(cgRect)
        setFrame(nsRect, display: true)
        contentView?.frame = NSRect(origin: .zero, size: nsRect.size)
        contentView?.needsDisplay = true
    }

    func animateFrame(to cgRect: CGRect, duration: TimeInterval, completion: (() -> Void)? = nil) {
        let nsRect = Self.cgToNS(cgRect)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(nsRect, display: true)
        } completionHandler: {
            self.contentView?.frame = NSRect(origin: .zero, size: nsRect.size)
            self.contentView?.needsDisplay = true
            completion?()
        }
    }

    static func cgToNS(_ cgRect: CGRect) -> NSRect {
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

private final class DividerView: NSView {
    var edge: EdgePosition = .right
    weak var barrierWindow: BarrierWindow?

    private var isDragging = false
    private var dragStartPoint: NSPoint = .zero
    private var dragStartSize: CGFloat = 0
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    private var isHorizontalEdge: Bool {
        edge == .left || edge == .right
    }

    override func draw(_ dirtyRect: NSRect) {
        // Background
        if isDragging {
            NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
        } else {
            NSColor.controlBackgroundColor.withAlphaComponent(0.6).setFill()
        }
        bounds.fill()

        // Edge line
        let lineWidth: CGFloat = 1
        NSColor.separatorColor.withAlphaComponent(0.6).setFill()
        switch edge {
        case .right:
            NSRect(x: 0, y: 0, width: lineWidth, height: bounds.height).fill()
        case .left:
            NSRect(x: bounds.width - lineWidth, y: 0, width: lineWidth, height: bounds.height).fill()
        case .top:
            NSRect(x: 0, y: 0, width: bounds.width, height: lineWidth).fill()
        case .bottom:
            NSRect(x: 0, y: bounds.height - lineWidth, width: bounds.width, height: lineWidth).fill()
        }

        // Grip indicator (three dots in center)
        let gripColor = isDragging
            ? NSColor.controlAccentColor.withAlphaComponent(0.8)
            : NSColor.secondaryLabelColor.withAlphaComponent(0.5)
        gripColor.setFill()

        let dotSize: CGFloat = 2
        let spacing: CGFloat = 4
        if isHorizontalEdge {
            let cx = bounds.midX
            let cy = bounds.midY
            for i in -1...1 {
                let y = cy + CGFloat(i) * spacing - dotSize / 2
                NSBezierPath(ovalIn: NSRect(x: cx - dotSize / 2, y: y, width: dotSize, height: dotSize)).fill()
            }
        } else {
            let cx = bounds.midX
            let cy = bounds.midY
            for i in -1...1 {
                let x = cx + CGFloat(i) * spacing - dotSize / 2
                NSBezierPath(ovalIn: NSRect(x: x, y: cy - dotSize / 2, width: dotSize, height: dotSize)).fill()
            }
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if isHorizontalEdge {
            NSCursor.resizeLeftRight.set()
        } else {
            NSCursor.resizeUpDown.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        dragStartPoint = NSEvent.mouseLocation
        dragStartSize = barrierWindow?.reservedAreaSize ?? 0
        Log.info("DividerView mouseDown edge=\(edge.rawValue) startSize=\(dragStartSize)")
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let currentPoint = NSEvent.mouseLocation
        let delta: CGFloat
        switch edge {
        case .right:
            delta = dragStartPoint.x - currentPoint.x
        case .left:
            delta = currentPoint.x - dragStartPoint.x
        case .top:
            delta = currentPoint.y - dragStartPoint.y
        case .bottom:
            delta = dragStartPoint.y - currentPoint.y
        }
        let newSize = max(100, dragStartSize + delta)
        guard let window = barrierWindow else { return }
        window.resizeDelegate?.barrierWindow(window, didDragToSize: newSize)
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            needsDisplay = true
            NSCursor.arrow.set()
        }
    }

}
