import CoreGraphics
import Carbon
import AppKit

final class HotkeyManager {
    typealias HotkeyHandler = () -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: HotkeyHandler?
    private var hotkeyConfig: HotkeyConfig = .defaultHotkey

    func register(config: HotkeyConfig = AppConfig.shared.hotkey, handler: @escaping HotkeyHandler) {
        if eventTap != nil { unregister() }

        self.handler = handler
        self.hotkeyConfig = config

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.info("Failed to create event tap. Is Accessibility permission granted?")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.info("Hotkey registered: \(config.displayString)")
    }

    func updateHotkey(_ config: HotkeyConfig) {
        guard let handler = self.handler else { return }
        hotkeyConfig = config
        AppConfig.shared.hotkey = config
        AppConfig.shared.save()
        register(config: config, handler: handler)
    }

    func unregister() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
        runLoopSource = nil
        handler = nil
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        let requiredFlags = CGEventFlags(rawValue: hotkeyConfig.modifiers)
        let modifierMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskControl]
        let activeModifiers = flags.intersection(modifierMask)

        if keyCode == hotkeyConfig.keyCode && activeModifiers == requiredFlags {
            handler?()
            return nil
        }

        return Unmanaged.passRetained(event)
    }
}
