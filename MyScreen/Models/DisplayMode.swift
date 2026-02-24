import CoreGraphics

struct DisplayMode: Identifiable, Equatable {
    let id: String
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    let isNative: Bool
    let cgMode: CGDisplayMode

    var isHiDPI: Bool { pixelWidth > width }

    var dimensionLabel: String {
        let base = "\(width) x \(height)"
        if refreshRate > 0 && refreshRate != 60 {
            return "\(base) @ \(Int(refreshRate))Hz"
        }
        return base
    }

    init(cgMode: CGDisplayMode) {
        self.cgMode = cgMode
        self.width = cgMode.width
        self.height = cgMode.height
        self.pixelWidth = cgMode.pixelWidth
        self.pixelHeight = cgMode.pixelHeight
        self.refreshRate = cgMode.refreshRate
        self.isNative = cgMode.ioFlags & 0x02000000 != 0 // kDisplayModeNativeFlag
        self.id = "\(width)x\(height)_\(pixelWidth)x\(pixelHeight)_\(Int(refreshRate))"
    }

    static func == (lhs: DisplayMode, rhs: DisplayMode) -> Bool {
        lhs.id == rhs.id
    }
}

struct DisplayModeGroup: Identifiable {
    let id: String
    let width: Int
    let height: Int
    let modes: [DisplayMode]

    var hasHiDPI: Bool { modes.contains { $0.isHiDPI } }
    var hasNonHiDPI: Bool { modes.contains { !$0.isHiDPI } }

    init(width: Int, height: Int, modes: [DisplayMode]) {
        self.width = width
        self.height = height
        self.id = "\(width)x\(height)"
        // HiDPI first, then by refresh rate descending
        self.modes = modes.sorted { a, b in
            if a.isHiDPI != b.isHiDPI { return a.isHiDPI }
            return a.refreshRate > b.refreshRate
        }
    }
}
