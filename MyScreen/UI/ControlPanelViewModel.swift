import SwiftUI
import CoreGraphics

extension Notification.Name {
    static let myScreenBindingStateDidChange = Notification.Name("MyScreenBindingStateDidChange")
}

final class ControlPanelViewModel: ObservableObject {
    @Published var displays: [DisplayInfo] = []
    @Published var selectedDisplayID: CGDirectDisplayID?
    @Published var slots: [ReservedSlot] = []
    @Published var expandedSlotID: UUID?
    @Published var showAppPicker: Bool = false
    @Published var hotkeyConfig: HotkeyConfig = .defaultHotkey
    @Published var brightness: Float = 1.0
    @Published var brightnessControlMethod: BrightnessControlMethod = .unavailable
    @Published private(set) var invalidBindingSlotIDs: Set<UUID> = []

    /// Which slot the app picker is for
    var appPickerSlotID: UUID?
    var preferredBundleIdentifierForPicker: String?
    private var brightnessDebounceTimer: Timer?
    private var bindingStateObserver: NSObjectProtocol?

    weak var screenManager: ScreenManager?

    init() {
        bindingStateObserver = NotificationCenter.default.addObserver(
            forName: .myScreenBindingStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshBindingStatus()
        }
    }

    deinit {
        if let bindingStateObserver {
            NotificationCenter.default.removeObserver(bindingStateObserver)
        }
    }

    func refresh() {
        guard let sm = screenManager else {
            Log.info("ViewModel.refresh: screenManager is nil")
            return
        }
        displays = sm.displayManager.displays
        hotkeyConfig = AppConfig.shared.hotkey

        if selectedDisplayID == nil || !displays.contains(where: { $0.displayID == selectedDisplayID }) {
            selectedDisplayID = displays.first?.displayID
        }

        if let displayID = selectedDisplayID {
            let layout = AppConfig.shared.layout(for: displayID)
            slots = layout.slots
            // Auto-expand first slot if none expanded
            if expandedSlotID == nil, let first = slots.first {
                expandedSlotID = first.id
            }
        }

        refreshBindingStatus()
        refreshBrightness()
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
        guard selectedDisplayID != nil else { return }
        var layout = currentLayout
        if let slot = layout.addSlot() {
            AppConfig.shared.setLayout(layout)
            slots = layout.slots
            expandedSlotID = slot.id
            refreshBindingStatus()
            screenManager?.applyConfiguration()
        }
    }

    func removeSlot(_ slotID: UUID) {
        guard selectedDisplayID != nil else { return }
        var layout = currentLayout
        layout.removeSlot(id: slotID)
        AppConfig.shared.setLayout(layout)
        slots = layout.slots
        if expandedSlotID == slotID {
            expandedSlotID = slots.first?.id
        }
        refreshBindingStatus()
        screenManager?.applyConfiguration()
    }

    func toggleSlotActive(_ slotID: UUID) {
        guard var slot = slots.first(where: { $0.id == slotID }) else { return }
        slot.isActive.toggle()
        updateSlot(slot)
    }

    func setSlotEdge(_ slotID: UUID, edge: EdgePosition) {
        guard var slot = slots.first(where: { $0.id == slotID }) else { return }
        guard currentLayout.canUseEdge(edge, excluding: slotID) else {
            Log.info("setSlotEdge rejected duplicate edge=\(edge.rawValue) for slot \(slotID)")
            return
        }
        slot.reservedArea.edge = edge
        updateSlot(slot)
    }

    func setSlotSizeType(_ slotID: UUID, type: String) {
        guard var slot = slots.first(where: { $0.id == slotID }) else { return }
        let currentType = slotSizeType(slot)
        guard currentType != type else { return }
        guard let baseLength = sizeReferenceLength(for: slot) else {
            Log.info("setSlotSizeType skipped, missing display context for slot \(slotID)")
            return
        }

        switch type {
        case "pixels":
            let percentage: CGFloat
            switch slot.reservedArea.size {
            case .percentage(let value):
                percentage = value
            case .pixels:
                updateSlot(slot)
                return
            }
            slot.reservedArea.size = .pixels(max(100, percentage * baseLength))
        case "percentage":
            let pixels: CGFloat
            switch slot.reservedArea.size {
            case .pixels(let value):
                pixels = value
            case .percentage:
                updateSlot(slot)
                return
            }
            slot.reservedArea.size = .percentage(min(max(pixels / baseLength, 0), 1))
        default:
            return
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

    func showAppPickerForSlot(_ slotID: UUID, preferredBundleIdentifier: String? = nil) {
        appPickerSlotID = slotID
        preferredBundleIdentifierForPicker = preferredBundleIdentifier
        showAppPicker = true
    }

    func bindApp(_ app: AppBinding) {
        guard let slotID = appPickerSlotID,
              var slot = slots.first(where: { $0.id == slotID }) else { return }
        slot.boundApp = app
        showAppPicker = false
        appPickerSlotID = nil
        preferredBundleIdentifierForPicker = nil
        updateSlot(slot)
    }

    func unbindApp(_ slotID: UUID) {
        guard var slot = slots.first(where: { $0.id == slotID }) else { return }
        slot.boundApp = nil
        updateSlot(slot)
    }

    func cancelAppPicker() {
        showAppPicker = false
        appPickerSlotID = nil
        preferredBundleIdentifierForPicker = nil
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

    func bindingMissing(for slotID: UUID) -> Bool {
        invalidBindingSlotIDs.contains(slotID)
    }

    private func updateSlot(_ slot: ReservedSlot) {
        guard selectedDisplayID != nil else { return }
        var layout = currentLayout
        layout.updateSlot(slot)
        AppConfig.shared.setLayout(layout)
        slots = layout.slots
        refreshBindingStatus()
        screenManager?.applyConfiguration()
    }

    private func sizeReferenceLength(for slot: ReservedSlot) -> CGFloat? {
        guard let displayID = selectedDisplayID,
              let display = displays.first(where: { $0.displayID == displayID }) else {
            return nil
        }

        switch slot.reservedArea.edge {
        case .left, .right:
            return display.visibleFrame.width
        case .top, .bottom:
            return display.visibleFrame.height
        }
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

    private func refreshBindingStatus() {
        invalidBindingSlotIDs = Set(
            slots.compactMap { slot in
                guard slot.isActive, let binding = slot.boundApp else { return nil }
                return WindowController.bestWindow(for: binding) == nil ? slot.id : nil
            }
        )
    }
}
