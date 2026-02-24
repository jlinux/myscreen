import SwiftUI
import CoreGraphics

final class ControlPanelViewModel: ObservableObject {
    @Published var displays: [DisplayInfo] = []
    @Published var selectedDisplayID: CGDirectDisplayID?
    @Published var slots: [ReservedSlot] = []
    @Published var expandedSlotID: UUID?
    @Published var showAppPicker: Bool = false
    @Published var hotkeyConfig: HotkeyConfig = .defaultHotkey
    @Published var brightness: Float = 1.0
    @Published var brightnessControlMethod: BrightnessControlMethod = .unavailable
    @Published var displayModeGroups: [DisplayModeGroup] = []
    @Published var currentDisplayMode: DisplayMode?
    @Published var isResolutionExpanded: Bool = false

    /// Which slot the app picker is for
    var appPickerSlotID: UUID?
    private var brightnessDebounceTimer: Timer?
    private let resolutionManager = ResolutionManager()
    private let fallbackDisplayManager = DisplayManager()

    weak var screenManager: ScreenManager?

    func refresh() {
        // Load display list regardless of screenManager availability
        let dm = screenManager?.displayManager ?? fallbackDisplayManager
        displays = dm.displays

        if selectedDisplayID == nil {
            selectedDisplayID = displays.first?.displayID
        }

        if let sm = screenManager {
            hotkeyConfig = AppConfig.shared.hotkey

            if let displayID = selectedDisplayID {
                let layout = AppConfig.shared.layout(for: displayID)
                slots = layout.slots
                if expandedSlotID == nil, let first = slots.first {
                    expandedSlotID = first.id
                }
            }

            refreshBrightness()
        }

        refreshResolution()
    }

    func refreshResolution() {
        guard let displayID = selectedDisplayID else {
            displayModeGroups = []
            currentDisplayMode = nil
            return
        }
        displayModeGroups = resolutionManager.groupedModes(for: displayID)
        currentDisplayMode = resolutionManager.currentMode(for: displayID)
        Log.info("refreshResolution: displayID=\(displayID) groups=\(displayModeGroups.count) current=\(currentDisplayMode?.dimensionLabel ?? "nil")")
    }

    func switchResolution(to mode: DisplayMode) {
        guard let displayID = selectedDisplayID else { return }
        Log.info("switchResolution: \(mode.dimensionLabel) hiDPI=\(mode.isHiDPI) id=\(mode.id)")
        if resolutionManager.setMode(mode, for: displayID) {
            currentDisplayMode = mode
            // Refresh after mode change (cache merges new modes, preserving HiDPI)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.refreshResolution()
            }
        }
    }

    func refreshBrightness() {
        guard let displayID = selectedDisplayID else {
            brightnessControlMethod = .unavailable
            return
        }
        let method = BrightnessManager.shared.controlMethod(for: displayID)
        let raw = BrightnessManager.shared.getBrightness(for: displayID)
        Log.info("refreshBrightness: displayID=\(displayID) method=\(method) raw=\(String(describing: raw))")
        brightnessControlMethod = method
        brightness = raw ?? 1.0
    }

    func setBrightness(_ value: Float) {
        brightness = value
        brightnessDebounceTimer?.invalidate()
        brightnessDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: false) { [weak self] _ in
            guard let self = self, let displayID = self.selectedDisplayID else { return }
            BrightnessManager.shared.setBrightness(for: displayID, to: value)
        }
    }

    var currentLayout: ScreenLayout {
        guard let displayID = selectedDisplayID else {
            return .defaultLayout(for: 0)
        }
        return AppConfig.shared.layout(for: displayID)
    }

    var canAddSlot: Bool {
        currentLayout.availableEdges.count > 0
    }

    // MARK: - Slot Operations

    func addSlot() {
        guard let displayID = selectedDisplayID else { return }
        var layout = currentLayout
        if let slot = layout.addSlot() {
            AppConfig.shared.setLayout(layout)
            slots = layout.slots
            expandedSlotID = slot.id
            screenManager?.applyConfiguration()
        }
    }

    func removeSlot(_ slotID: UUID) {
        guard let displayID = selectedDisplayID else { return }
        var layout = currentLayout
        layout.removeSlot(id: slotID)
        AppConfig.shared.setLayout(layout)
        slots = layout.slots
        if expandedSlotID == slotID {
            expandedSlotID = slots.first?.id
        }
        screenManager?.applyConfiguration()
    }

    func toggleSlotActive(_ slotID: UUID) {
        guard var slot = slots.first(where: { $0.id == slotID }) else { return }
        slot.isActive.toggle()
        updateSlot(slot)
    }

    func setSlotEdge(_ slotID: UUID, edge: EdgePosition) {
        guard var slot = slots.first(where: { $0.id == slotID }) else { return }
        slot.reservedArea.edge = edge
        updateSlot(slot)
    }

    func setSlotSizeType(_ slotID: UUID, type: String) {
        guard var slot = slots.first(where: { $0.id == slotID }) else { return }
        switch type {
        case "pixels":
            let current = slotSizeValue(slot)
            slot.reservedArea.size = .pixels(current)
        case "percentage":
            let current = slotSizeValue(slot)
            slot.reservedArea.size = .percentage(current / 100)
        default: break
        }
        updateSlot(slot)
    }

    func setSlotSizeValue(_ slotID: UUID, value: CGFloat) {
        guard var slot = slots.first(where: { $0.id == slotID }) else { return }
        switch slot.reservedArea.size {
        case .pixels:
            slot.reservedArea.size = .pixels(value)
        case .percentage:
            slot.reservedArea.size = .percentage(value / 100)
        }
        updateSlot(slot)
    }

    func showAppPickerForSlot(_ slotID: UUID) {
        appPickerSlotID = slotID
        showAppPicker = true
    }

    func bindApp(_ app: AppBinding) {
        guard let slotID = appPickerSlotID,
              var slot = slots.first(where: { $0.id == slotID }) else { return }
        slot.boundApp = app
        showAppPicker = false
        appPickerSlotID = nil
        updateSlot(slot)
    }

    func unbindApp(_ slotID: UUID) {
        guard var slot = slots.first(where: { $0.id == slotID }) else { return }
        slot.boundApp = nil
        updateSlot(slot)
    }

    // MARK: - Helpers

    func slotSizeType(_ slot: ReservedSlot) -> String {
        switch slot.reservedArea.size {
        case .pixels: return "pixels"
        case .percentage: return "percentage"
        }
    }

    func slotSizeValue(_ slot: ReservedSlot) -> CGFloat {
        switch slot.reservedArea.size {
        case .pixels(let v): return v
        case .percentage(let v): return v * 100
        }
    }

    func usedEdges(excluding slotID: UUID) -> Set<EdgePosition> {
        Set(slots.filter { $0.id != slotID }.map { $0.reservedArea.edge })
    }

    private func updateSlot(_ slot: ReservedSlot) {
        guard let displayID = selectedDisplayID else { return }
        var layout = currentLayout
        layout.updateSlot(slot)
        AppConfig.shared.setLayout(layout)
        slots = layout.slots
        screenManager?.applyConfiguration()
    }

    func selectDisplay(_ id: CGDirectDisplayID) {
        selectedDisplayID = id
        expandedSlotID = nil
        refresh()
    }

    func updateHotkey(_ config: HotkeyConfig) {
        Log.info("updateHotkey: \(config.displayString)")
        hotkeyConfig = config
        screenManager?.hotkeyManager.updateHotkey(config)
    }
}
