import SwiftUI
import CoreGraphics

final class ControlPanelViewModel: ObservableObject {
    @Published var displays: [DisplayInfo] = []
    @Published var selectedDisplayID: CGDirectDisplayID?
    @Published var isActive: Bool = false
    @Published var edge: EdgePosition = .right
    @Published var sizeType: String = "percentage"  // "pixels" or "percentage"
    @Published var sizeValue: CGFloat = 30
    @Published var boundApp: AppBinding?
    @Published var showAppPicker: Bool = false

    weak var screenManager: ScreenManager?

    func refresh() {
        guard let sm = screenManager else { return }
        displays = sm.displayManager.displays

        if selectedDisplayID == nil {
            selectedDisplayID = displays.first?.displayID
        }

        if let displayID = selectedDisplayID {
            let layout = AppConfig.shared.layout(for: displayID)
            isActive = layout.isActive
            edge = layout.reservedArea.edge
            boundApp = layout.boundApp
            switch layout.reservedArea.size {
            case .pixels(let v):
                sizeType = "pixels"
                sizeValue = v
            case .percentage(let v):
                sizeType = "percentage"
                sizeValue = v * 100
            }
        }
    }

    func applyChanges() {
        guard let displayID = selectedDisplayID else { return }

        let size: SizeSpec = sizeType == "pixels"
            ? .pixels(sizeValue)
            : .percentage(sizeValue / 100)

        var layout = ScreenLayout(
            displayID: displayID,
            reservedArea: ReservedArea(edge: edge, size: size),
            boundApp: boundApp,
            isActive: isActive
        )
        _ = layout // suppress warning

        AppConfig.shared.setLayout(ScreenLayout(
            displayID: displayID,
            reservedArea: ReservedArea(edge: edge, size: size),
            boundApp: boundApp,
            isActive: isActive
        ))

        screenManager?.applyConfiguration()
    }

    func selectDisplay(_ id: CGDirectDisplayID) {
        selectedDisplayID = id
        refresh()
    }

    func toggleActive() {
        isActive.toggle()
        applyChanges()
    }

    func setEdge(_ newEdge: EdgePosition) {
        edge = newEdge
        applyChanges()
    }

    func bindApp(_ app: AppBinding) {
        boundApp = app
        showAppPicker = false
        applyChanges()
    }

    func unbindApp() {
        boundApp = nil
        applyChanges()
    }
}
