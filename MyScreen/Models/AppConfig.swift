import Foundation
import CoreGraphics

struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt64  // CGEventFlags rawValue

    /// Default: ⌘⌥M
    static let defaultHotkey = HotkeyConfig(keyCode: 46, modifiers: CGEventFlags([.maskCommand, .maskAlternate]).rawValue)

    var displayString: String {
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: modifiers)
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        parts.append(Self.keyCodeToString(keyCode))
        return parts.joined()
    }

    private static func keyCodeToString(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
            38: "J", 40: "K", 45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7",
            28: "8", 25: "9", 29: "0",
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete",
            53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return keyMap[keyCode] ?? "Key\(keyCode)"
    }
}

final class AppConfig {
    static let shared = AppConfig()

    private let key = "com.myscreen.config"
    private let queue = DispatchQueue(label: "com.myscreen.config.queue")

    private var _layouts: [CGDirectDisplayID: ScreenLayout] = [:]
    private var _globalHotkeyEnabled: Bool = true
    private var _hotkey: HotkeyConfig = .defaultHotkey

    var layouts: [CGDirectDisplayID: ScreenLayout] {
        get { queue.sync { _layouts } }
        set { queue.sync { _layouts = newValue } }
    }
    var globalHotkeyEnabled: Bool {
        get { queue.sync { _globalHotkeyEnabled } }
        set { queue.sync { _globalHotkeyEnabled = newValue } }
    }
    var hotkey: HotkeyConfig {
        get { queue.sync { _hotkey } }
        set { queue.sync { _hotkey = newValue } }
    }

    private init() {
        load()
    }

    func layout(for displayID: CGDirectDisplayID) -> ScreenLayout {
        queue.sync { _layouts[displayID] ?? .defaultLayout(for: displayID) }
    }

    func setLayout(_ layout: ScreenLayout) {
        queue.sync { _layouts[layout.displayID] = layout }
        save()
    }

    // MARK: - Persistence

    var isScreenHidden: Bool {
        get { queue.sync { _isScreenHidden } }
        set { queue.sync { _isScreenHidden = newValue } }
    }
    private var _isScreenHidden: Bool = false

    private struct StoredConfig: Codable {
        var layouts: [ScreenLayoutEntry]
        var globalHotkeyEnabled: Bool
        var hotkey: HotkeyConfig?
        var isScreenHidden: Bool?
    }

    private struct ScreenLayoutEntry: Codable {
        var displayID: UInt32
        var reservedArea: ReservedArea
        var boundApp: AppBinding?
        var isActive: Bool
    }

    func save() {
        let stored: StoredConfig = queue.sync {
            let entries = _layouts.values.map { layout in
                ScreenLayoutEntry(
                    displayID: layout.displayID,
                    reservedArea: layout.reservedArea,
                    boundApp: layout.boundApp,
                    isActive: layout.isActive
                )
            }
            return StoredConfig(
                layouts: entries,
                globalHotkeyEnabled: _globalHotkeyEnabled,
                hotkey: _hotkey,
                isScreenHidden: _isScreenHidden
            )
        }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode(StoredConfig.self, from: data) else {
            return
        }
        queue.sync {
            _globalHotkeyEnabled = stored.globalHotkeyEnabled
            _hotkey = stored.hotkey ?? .defaultHotkey
            _isScreenHidden = stored.isScreenHidden ?? false
            _layouts = [:]
            for entry in stored.layouts {
                let layout = ScreenLayout(
                    displayID: entry.displayID,
                    reservedArea: entry.reservedArea,
                    boundApp: entry.boundApp,
                    isActive: entry.isActive
                )
                _layouts[entry.displayID] = layout
            }
        }
    }
}
