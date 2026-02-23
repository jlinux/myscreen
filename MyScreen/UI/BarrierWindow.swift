import AppKit

protocol BarrierWindowDelegate: AnyObject {
    func barrierWindow(_ window: BarrierWindow, didDragToSize newSize: CGFloat)
}

final class BarrierWindow: NSWindow {
    weak var resizeDelegate: BarrierWindowDelegate?
    var edge: EdgePosition = .right

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

    private let dragHandleWidth: CGFloat = 8
    private var isDragging = false
    private var dragStartPoint: NSPoint = .zero
    private var dragStartSize: CGFloat = 0
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: dragHandleRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    private var dragHandleRect: NSRect {
        switch edge {
        case .right:
            return NSRect(x: 0, y: 0, width: dragHandleWidth, height: bounds.height)
        case .left:
            return NSRect(x: bounds.width - dragHandleWidth, y: 0, width: dragHandleWidth, height: bounds.height)
        case .top:
            return NSRect(x: 0, y: 0, width: bounds.width, height: dragHandleWidth)
        case .bottom:
            return NSRect(x: 0, y: bounds.height - dragHandleWidth, width: bounds.width, height: dragHandleWidth)
        }
    }

    private var isHorizontalEdge: Bool {
        edge == .left || edge == .right
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.withAlphaComponent(0.05).setFill()
        bounds.fill()

        let lineWidth: CGFloat = 2
        NSColor.separatorColor.withAlphaComponent(0.5).setFill()
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

        if isDragging {
            NSColor.controlAccentColor.withAlphaComponent(0.3).setFill()
            dragHandleRect.fill()
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
        let point = convert(event.locationInWindow, from: nil)
        if dragHandleRect.contains(point) {
            isDragging = true
            dragStartPoint = NSEvent.mouseLocation
            dragStartSize = isHorizontalEdge ? bounds.width : bounds.height
            needsDisplay = true
        }
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
        barrierWindow?.resizeDelegate?.barrierWindow(barrierWindow!, didDragToSize: newSize)
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            needsDisplay = true
            NSCursor.arrow.set()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        if dragHandleRect.contains(localPoint) {
            return self
        }
        return nil
    }
}
