import CoreGraphics
import Foundation

/// Result for a single slot calculation.
struct SlotLayoutResult {
    let reservedRect: CGRect
    let dividerRect: CGRect
}

/// Result for multi-slot layout calculation.
struct LayoutResult {
    /// Per-slot rects, keyed by slot UUID.
    let slotResults: [UUID: SlotLayoutResult]
    /// Work area after all reserved areas are subtracted.
    let workAreaRect: CGRect
}

enum LayoutEngine {
    private static let dividerWidth: CGFloat = 8

    /// Calculate layout for multiple reserved area slots on one screen.
    static func calculate(screenFrame: CGRect, slots: [ReservedSlot]) -> LayoutResult {
        let activeSlots = slots.filter { $0.isActive }
        var workArea = screenFrame
        var slotResults: [UUID: SlotLayoutResult] = [:]

        for slot in activeSlots {
            let area = slot.reservedArea
            let reservedRect: CGRect

            switch area.edge {
            case .left:
                let w = area.size.resolve(for: workArea.width)
                reservedRect = CGRect(x: workArea.origin.x, y: workArea.origin.y, width: w, height: workArea.height)
                workArea = CGRect(x: workArea.origin.x + w, y: workArea.origin.y, width: workArea.width - w, height: workArea.height)
            case .right:
                let w = area.size.resolve(for: workArea.width)
                reservedRect = CGRect(x: workArea.origin.x + workArea.width - w, y: workArea.origin.y, width: w, height: workArea.height)
                workArea = CGRect(x: workArea.origin.x, y: workArea.origin.y, width: workArea.width - w, height: workArea.height)
            case .top:
                let h = area.size.resolve(for: workArea.height)
                reservedRect = CGRect(x: workArea.origin.x, y: workArea.origin.y, width: workArea.width, height: h)
                workArea = CGRect(x: workArea.origin.x, y: workArea.origin.y + h, width: workArea.width, height: workArea.height - h)
            case .bottom:
                let h = area.size.resolve(for: workArea.height)
                reservedRect = CGRect(x: workArea.origin.x, y: workArea.origin.y + workArea.height - h, width: workArea.width, height: h)
                workArea = CGRect(x: workArea.origin.x, y: workArea.origin.y, width: workArea.width, height: workArea.height - h)
            }

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

            slotResults[slot.id] = SlotLayoutResult(reservedRect: reservedRect, dividerRect: dividerRect)
        }

        return LayoutResult(slotResults: slotResults, workAreaRect: workArea)
    }

    /// Convenience: single-slot calculation (backward compat).
    static func calculate(screenFrame: CGRect, area: ReservedArea) -> SlotLayoutResult {
        let slot = ReservedSlot(reservedArea: area)
        let result = calculate(screenFrame: screenFrame, slots: [slot])
        return result.slotResults.values.first ?? SlotLayoutResult(reservedRect: .zero, dividerRect: .zero)
    }
}
