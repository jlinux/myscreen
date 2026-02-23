import Foundation
import CoreGraphics

struct ScreenLayout: Codable, Equatable {
    let displayID: CGDirectDisplayID
    var reservedArea: ReservedArea
    var boundApp: AppBinding?
    var isActive: Bool

    static func defaultLayout(for displayID: CGDirectDisplayID) -> ScreenLayout {
        ScreenLayout(
            displayID: displayID,
            reservedArea: .defaultArea,
            boundApp: nil,
            isActive: false
        )
    }
}
