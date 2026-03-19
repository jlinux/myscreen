import Foundation
import CoreGraphics

struct WindowFrameSnapshot: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(frame: CGRect) {
        x = frame.origin.x
        y = frame.origin.y
        width = frame.width
        height = frame.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct AppBinding: Codable, Equatable {
    let bundleIdentifier: String
    let displayName: String
    let windowIdentifier: String?
    let windowTitle: String?
    let windowSubrole: String?
    let lastKnownFrame: WindowFrameSnapshot?

    var isWindowSpecific: Bool {
        windowIdentifier != nil || windowTitle != nil || windowSubrole != nil
    }

    var displayLabel: String {
        guard let windowTitle, !windowTitle.isEmpty else { return displayName }
        return "\(displayName) - \(windowTitle)"
    }
}
