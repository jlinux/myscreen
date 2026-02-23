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
        guard let sm = screenManager else {
            Log.info("ViewModel.refresh: screenManager is nil")
            return
        }
        displays = sm.displayManager.displays
        Log.info("ViewModel.refresh: \(displays.count) displays")

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
            Log.info("ViewModel.refresh: displayID=\(displayID) isActive=\(isActive) edge=\(edge.rawValue) boundApp=\(boundApp?.displayName ?? "none")")
        }
    }

    func applyChanges() {
        guard let displayID = selectedDisplayID else {
            Log.info("applyChanges: no selectedDisplayID")
            return
        }

        let size: SizeSpec = sizeType == "pixels"
            ? .pixels(sizeValue)
            : .percentage(sizeValue / 100)

        let layout = ScreenLayout(
            displayID: displayID,
            reservedArea: ReservedArea(edge: edge, size: size),
            boundApp: boundApp,
            isActive: isActive
        )

        Log.info("applyChanges: displayID=\(displayID) isActive=\(isActive) edge=\(edge.rawValue) boundApp=\(boundApp?.displayName ?? "none")")

        AppConfig.shared.setLayout(layout)

        if screenManager == nil {
            Log.info("WARNING: screenManager is nil!")
        }
        screenManager?.applyConfiguration()
    }

    func selectDisplay(_ id: CGDirectDisplayID) {
        Log.info("selectDisplay: \(id)")
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
        Log.info("bindApp: \(app.displayName) (\(app.bundleIdentifier))")
        boundApp = app
        showAppPicker = false
        applyChanges()
    }

    func unbindApp() {
        boundApp = nil
        applyChanges()
    }
}
