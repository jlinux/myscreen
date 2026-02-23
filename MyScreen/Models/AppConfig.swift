import Foundation
import CoreGraphics

final class AppConfig {
    static let shared = AppConfig()

    private let key = "com.myscreen.config"

    var layouts: [CGDirectDisplayID: ScreenLayout] = [:]
    var globalHotkeyEnabled: Bool = true

    private init() {
        load()
    }

    func layout(for displayID: CGDirectDisplayID) -> ScreenLayout {
        layouts[displayID] ?? .defaultLayout(for: displayID)
    }

    func setLayout(_ layout: ScreenLayout) {
        layouts[layout.displayID] = layout
        save()
    }

    // MARK: - Persistence

    private struct StoredConfig: Codable {
        var layouts: [ScreenLayoutEntry]
        var globalHotkeyEnabled: Bool
    }

    private struct ScreenLayoutEntry: Codable {
        var displayID: UInt32
        var reservedArea: ReservedArea
        var boundApp: AppBinding?
        var isActive: Bool
    }

    func save() {
        let entries = layouts.values.map { layout in
            ScreenLayoutEntry(
                displayID: layout.displayID,
                reservedArea: layout.reservedArea,
                boundApp: layout.boundApp,
                isActive: layout.isActive
            )
        }
        let stored = StoredConfig(layouts: entries, globalHotkeyEnabled: globalHotkeyEnabled)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode(StoredConfig.self, from: data) else {
            return
        }
        globalHotkeyEnabled = stored.globalHotkeyEnabled
        layouts = [:]
        for entry in stored.layouts {
            let layout = ScreenLayout(
                displayID: entry.displayID,
                reservedArea: entry.reservedArea,
                boundApp: entry.boundApp,
                isActive: entry.isActive
            )
            layouts[entry.displayID] = layout
        }
    }
}
