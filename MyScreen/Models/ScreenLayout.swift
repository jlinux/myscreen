import Foundation
import CoreGraphics

struct ReservedSlot: Codable, Equatable, Identifiable {
    let id: UUID
    var reservedArea: ReservedArea
    var boundApp: AppBinding?
    var isActive: Bool

    init(id: UUID = UUID(), reservedArea: ReservedArea = .defaultArea, boundApp: AppBinding? = nil, isActive: Bool = true) {
        self.id = id
        self.reservedArea = reservedArea
        self.boundApp = boundApp
        self.isActive = isActive
    }
}

struct ScreenLayout: Codable, Equatable {
    let displayID: CGDirectDisplayID
    var slots: [ReservedSlot]

    /// Convenience: first active slot's reservedArea (backward compat for simple cases)
    var reservedArea: ReservedArea {
        get { slots.first?.reservedArea ?? .defaultArea }
    }

    /// Convenience: first active slot's boundApp
    var boundApp: AppBinding? {
        get { slots.first?.boundApp }
    }

    /// True if any slot is active
    var isActive: Bool {
        get { slots.contains(where: { $0.isActive }) }
    }

    /// Edges already used by active slots
    var usedEdges: Set<EdgePosition> {
        Set(slots.map { $0.reservedArea.edge })
    }

    /// Available edges for a new slot
    var availableEdges: [EdgePosition] {
        EdgePosition.allCases.filter { !usedEdges.contains($0) }
    }

    static func defaultLayout(for displayID: CGDirectDisplayID) -> ScreenLayout {
        ScreenLayout(displayID: displayID, slots: [])
    }

    mutating func addSlot() -> ReservedSlot? {
        guard let edge = availableEdges.first else { return nil }
        let slot = ReservedSlot(reservedArea: ReservedArea(edge: edge, size: .percentage(0.3)))
        slots.append(slot)
        return slot
    }

    mutating func removeSlot(id: UUID) {
        slots.removeAll { $0.id == id }
    }

    mutating func updateSlot(_ slot: ReservedSlot) {
        guard let index = slots.firstIndex(where: { $0.id == slot.id }) else { return }
        slots[index] = slot
    }

    func slot(for id: UUID) -> ReservedSlot? {
        slots.first { $0.id == id }
    }
}
