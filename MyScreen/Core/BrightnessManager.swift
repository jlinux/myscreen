import Foundation
import CoreGraphics
import os.log

private let brightnessLog = OSLog(subsystem: "com.myscreen.app", category: "Brightness")

// MARK: - Control Method

enum BrightnessControlMethod {
    case displayServices
    case ddc
    case softwareGamma
    case unavailable
}

// MARK: - BrightnessManager

final class BrightnessManager {
    static let shared = BrightnessManager()

    // DisplayServices private framework function signatures
    private typealias CanChangeBrightnessFn = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias DSGetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DSSetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private var canChangeBrightness: CanChangeBrightnessFn?
    private var dsGetBrightness: DSGetBrightnessFn?
    private var dsSetBrightness: DSSetBrightnessFn?

    // DDC via IOAVService private API
    private typealias I2CReadFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
    private typealias I2CWriteFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
    private typealias AVServiceCreateWithLocationFn = @convention(c) (CFAllocator?, CFString) -> CFTypeRef?

    private var avServiceReadI2C: I2CReadFn?
    private var avServiceWriteI2C: I2CWriteFn?
    private var avServiceCreateWithLocation: AVServiceCreateWithLocationFn?

    /// Caches the IOAVService reference and max DDC brightness per display.
    private var ddcServiceCache: [CGDirectDisplayID: CFTypeRef] = [:]
    private var ddcMaxBrightness: [CGDirectDisplayID: UInt16] = [:]

    private var methodCache: [CGDirectDisplayID: BrightnessControlMethod] = [:]

    /// Tracks which displays have active software gamma adjustments and their brightness values.
    private var softwareGammaValues: [CGDirectDisplayID: Float] = [:]

    private static let gammaDefaultsKey = "SoftwareGammaBrightness"

    // DDC/CI constants
    private static let ddcChipAddress: UInt32 = 0x37
    private static let ddcHostAddress: UInt8 = 0x51
    private static let ddcDisplayAddress: UInt8 = 0x6E
    private static let ddcReplyAddress: UInt8 = 0x6F
    private static let vcpBrightness: UInt8 = 0x10

    private init() {
        loadDisplayServices()
        loadDDC()
        loadPersistedGamma()
        reapplySoftwareGamma()
    }

    // MARK: - Dynamic Library Loading

    private func loadDisplayServices() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else {
            Log.info("BrightnessManager: DisplayServices dlopen failed")
            return
        }

        if let sym = dlsym(handle, "DisplayServicesCanChangeBrightness") {
            canChangeBrightness = unsafeBitCast(sym, to: CanChangeBrightnessFn.self)
        }
        if let sym = dlsym(handle, "DisplayServicesGetBrightness") {
            dsGetBrightness = unsafeBitCast(sym, to: DSGetBrightnessFn.self)
        }
        if let sym = dlsym(handle, "DisplayServicesSetBrightness") {
            dsSetBrightness = unsafeBitCast(sym, to: DSSetBrightnessFn.self)
        }

        Log.info("BrightnessManager: DisplayServices loaded — get=\(dsGetBrightness != nil) set=\(dsSetBrightness != nil)")
    }

    private func loadDDC() {
        guard let ioHandle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else { return }

        if let sym = dlsym(ioHandle, "IOAVServiceReadI2C") {
            avServiceReadI2C = unsafeBitCast(sym, to: I2CReadFn.self)
        }
        if let sym = dlsym(ioHandle, "IOAVServiceWriteI2C") {
            avServiceWriteI2C = unsafeBitCast(sym, to: I2CWriteFn.self)
        }
        if let sym = dlsym(ioHandle, "IOAVServiceCreateWithLocation") {
            avServiceCreateWithLocation = unsafeBitCast(sym, to: AVServiceCreateWithLocationFn.self)
        }

        let ready = avServiceReadI2C != nil && avServiceWriteI2C != nil && avServiceCreateWithLocation != nil
        Log.info("BrightnessManager: DDC loaded — ready=\(ready)")
    }

    // MARK: - Public API

    func controlMethod(for displayID: CGDirectDisplayID) -> BrightnessControlMethod {
        if let cached = methodCache[displayID] { return cached }
        let method = detectControlMethod(for: displayID)
        methodCache[displayID] = method
        Log.info("BrightnessManager: display \(displayID) control method = \(method)")
        return method
    }

    func getBrightness(for displayID: CGDirectDisplayID) -> Float? {
        let method = controlMethod(for: displayID)
        switch method {
        case .displayServices:
            return getDisplayServicesBrightness(displayID)
        case .ddc:
            return getDDCBrightness(displayID)
        case .softwareGamma:
            return softwareGammaValues[displayID] ?? 1.0
        case .unavailable:
            return nil
        }
    }

    func setBrightness(for displayID: CGDirectDisplayID, to value: Float) {
        let clamped = min(max(value, 0.0), 1.0)
        let method = controlMethod(for: displayID)
        switch method {
        case .displayServices:
            setDisplayServicesBrightness(displayID, value: clamped)
        case .ddc:
            setDDCBrightness(displayID, value: clamped)
        case .softwareGamma:
            setSoftwareGamma(displayID, value: clamped)
        case .unavailable:
            break
        }
    }

    func invalidateCache() {
        methodCache.removeAll()
        ddcMaxBrightness.removeAll()
        ddcServiceCache.removeAll()
    }

    func resetSoftwareGamma(for displayID: CGDirectDisplayID) {
        CGDisplayRestoreColorSyncSettings()
        softwareGammaValues.removeValue(forKey: displayID)
        persistGamma()
        // Reapply remaining displays' gamma (RestoreColorSyncSettings resets all)
        for (id, val) in softwareGammaValues where id != displayID {
            let v = CGGammaValue(val)
            CGSetDisplayTransferByFormula(id, 0, v, 1.0, 0, v, 1.0, 0, v, 1.0)
        }
    }

    func resetAllSoftwareGamma() {
        if !softwareGammaValues.isEmpty {
            CGDisplayRestoreColorSyncSettings()
            softwareGammaValues.removeAll()
            persistGamma()
            Log.info("BrightnessManager: reset all software gamma")
        }
    }

    /// Reapply software gamma for all displays that had an active adjustment.
    func reapplySoftwareGamma() {
        for (displayID, value) in softwareGammaValues {
            setSoftwareGamma(displayID, value: value)
        }
    }

    // MARK: - Detection

    private func detectControlMethod(for displayID: CGDirectDisplayID) -> BrightnessControlMethod {
        // Tier 1: DisplayServices (built-in and Apple displays)
        if let getFn = dsGetBrightness {
            var brightness: Float = -1
            let result = getFn(displayID, &brightness)
            os_log("DisplayServices probe displayID=%u result=%d brightness=%f", log: brightnessLog, type: .info, displayID, result, brightness)
            if result == 0 && brightness >= 0.0 && brightness <= 1.0 {
                if let canChange = canChangeBrightness {
                    let changeable = canChange(displayID)
                    os_log("DisplayServices canChange=%d for displayID=%u", log: brightnessLog, type: .info, changeable ? 1 : 0, displayID)
                    if changeable {
                        return .displayServices
                    }
                } else {
                    return .displayServices
                }
            }
        }

        // Tier 2: DDC/CI (external displays via IOAVService I2C)
        if let service = avServiceForDisplay(displayID) {
            ddcServiceCache[displayID] = service
            if let (current, max) = ddcReadVCPWithService(service, vcpCode: Self.vcpBrightness) {
                os_log("DDC probe displayID=%u current=%u max=%u", log: brightnessLog, type: .info, displayID, current, max)
                if max > 0 {
                    ddcMaxBrightness[displayID] = max
                    // Clear any leftover software gamma for this display
                    if softwareGammaValues.removeValue(forKey: displayID) != nil {
                        CGDisplayRestoreColorSyncSettings()
                        // Reapply gamma for other displays that still need it
                        for (id, val) in softwareGammaValues {
                            let v = CGGammaValue(val)
                            CGSetDisplayTransferByFormula(id, 0, v, 1.0, 0, v, 1.0, 0, v, 1.0)
                        }
                        persistGamma()
                        Log.info("BrightnessManager: cleared leftover software gamma for DDC display \(displayID)")
                    }
                    return .ddc
                }
            }
        }

        // Tier 3: Software Gamma — always available as fallback
        return .softwareGamma
    }

    // MARK: - IOAVService Lookup

    /// Get an IOAVService for the given display. For non-built-in displays, uses IOAVServiceCreateWithLocation.
    private func avServiceForDisplay(_ displayID: CGDirectDisplayID) -> CFTypeRef? {
        if let cached = ddcServiceCache[displayID] { return cached }

        guard let createFn = avServiceCreateWithLocation else {
            os_log("DDC: IOAVServiceCreateWithLocation not available", log: brightnessLog, type: .info)
            return nil
        }

        // Determine if this display is the built-in one
        let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0

        if isBuiltIn {
            // Built-in displays don't support DDC
            os_log("DDC: displayID=%u is built-in, skipping DDC", log: brightnessLog, type: .info, displayID)
            return nil
        }

        // Try "External" location for external displays
        if let service = createFn(kCFAllocatorDefault, "External" as CFString) {
            os_log("DDC: got IOAVService for External display (displayID=%u)", log: brightnessLog, type: .info, displayID)
            return service
        }

        os_log("DDC: IOAVServiceCreateWithLocation('External') returned nil for displayID=%u", log: brightnessLog, type: .info, displayID)
        return nil
    }

    // MARK: - DisplayServices

    private func getDisplayServicesBrightness(_ displayID: CGDirectDisplayID) -> Float? {
        guard let getFn = dsGetBrightness else { return nil }
        var brightness: Float = -1
        let result = getFn(displayID, &brightness)
        guard result == 0, brightness >= 0.0, brightness <= 1.0 else { return nil }
        return brightness
    }

    private func setDisplayServicesBrightness(_ displayID: CGDirectDisplayID, value: Float) {
        guard let setFn = dsSetBrightness else { return }
        _ = setFn(displayID, value)
    }

    // MARK: - DDC/CI

    private func getDDCBrightness(_ displayID: CGDirectDisplayID) -> Float? {
        guard let service = ddcServiceCache[displayID] ?? avServiceForDisplay(displayID) else { return nil }
        guard let (current, max) = ddcReadVCPWithService(service, vcpCode: Self.vcpBrightness) else { return nil }
        if max == 0 { return nil }
        ddcMaxBrightness[displayID] = max
        return Float(current) / Float(max)
    }

    private func setDDCBrightness(_ displayID: CGDirectDisplayID, value: Float) {
        guard let service = ddcServiceCache[displayID] ?? avServiceForDisplay(displayID) else { return }
        let max = ddcMaxBrightness[displayID] ?? 100
        let intValue = UInt16(round(value * Float(max)))
        ddcWriteVCPWithService(service, vcpCode: Self.vcpBrightness, value: intValue)
    }

    /// Read a VCP value via DDC/CI using a pre-obtained IOAVService.
    private func ddcReadVCPWithService(_ service: CFTypeRef, vcpCode: UInt8) -> (UInt16, UInt16)? {
        guard let readFn = avServiceReadI2C,
              let writeFn = avServiceWriteI2C else {
            return nil
        }

        // Build VCP Get request
        let length: UInt8 = 0x82  // 0x80 | 2 data bytes
        let opcode: UInt8 = 0x01  // VCP Request
        let checksum = Self.ddcDisplayAddress ^ Self.ddcHostAddress ^ length ^ opcode ^ vcpCode

        var writeData: [UInt8] = [length, opcode, vcpCode, checksum]
        let writeResult = writeFn(service, Self.ddcChipAddress, UInt32(Self.ddcHostAddress),
                                  &writeData, UInt32(writeData.count))
        guard writeResult == 0 else {
            os_log("DDC I2C write failed result=%d", log: brightnessLog, type: .info, writeResult)
            return nil
        }

        // Wait for display to process
        usleep(40_000)  // 40ms

        // Read response — may include source address byte (0x6E) depending on API behavior
        var readData = [UInt8](repeating: 0, count: 12)
        let readResult = readFn(service, Self.ddcChipAddress, UInt32(Self.ddcReplyAddress),
                                &readData, UInt32(readData.count))
        guard readResult == 0 else {
            os_log("DDC I2C read failed result=%d", log: brightnessLog, type: .info, readResult)
            return nil
        }

        os_log("DDC raw response: %{public}@", log: brightnessLog, type: .info,
               readData.map { String(format: "%02X", $0) }.joined(separator: " "))

        // Find the start of the actual VCP reply.
        // If first byte is 0x6E (display source address), skip it.
        let offset = (readData[0] == Self.ddcDisplayAddress) ? 1 : 0

        // VCP Reply format (after optional 0x6E source address):
        // [0] length (0x88 = 8 data bytes)
        // [1] 0x02 = Feature Reply opcode
        // [2] result code (0x00 = No Error)
        // [3] VCP code
        // [4] type code
        // [5..6] max value (hi, lo)
        // [7..8] current value (hi, lo)
        // [9] checksum
        guard readData.count >= offset + 9,
              readData[offset] == 0x88,             // 8 data bytes follow
              readData[offset + 1] == 0x02,         // Feature Reply opcode
              readData[offset + 2] == 0x00,         // No Error
              readData[offset + 3] == vcpCode       // VCP code echoed
        else {
            os_log("DDC unexpected response (offset=%d): %{public}@", log: brightnessLog, type: .info, offset,
                   readData.map { String(format: "%02X", $0) }.joined(separator: " "))
            return nil
        }

        let maxValue = UInt16(readData[offset + 5]) << 8 | UInt16(readData[offset + 6])
        let curValue = UInt16(readData[offset + 7]) << 8 | UInt16(readData[offset + 8])

        return (curValue, maxValue)
    }

    /// Write a VCP value via DDC/CI using a pre-obtained IOAVService.
    private func ddcWriteVCPWithService(_ service: CFTypeRef, vcpCode: UInt8, value: UInt16) {
        guard let writeFn = avServiceWriteI2C else { return }

        let length: UInt8 = 0x84  // 0x80 | 4 data bytes
        let opcode: UInt8 = 0x03  // VCP Set
        let valueHi = UInt8(value >> 8)
        let valueLo = UInt8(value & 0xFF)
        let checksum = Self.ddcDisplayAddress ^ Self.ddcHostAddress ^ length ^ opcode ^ vcpCode ^ valueHi ^ valueLo

        var writeData: [UInt8] = [length, opcode, vcpCode, valueHi, valueLo, checksum]
        let result = writeFn(service, Self.ddcChipAddress, UInt32(Self.ddcHostAddress),
                             &writeData, UInt32(writeData.count))
        if result != 0 {
            os_log("DDC VCP Set failed result=%d", log: brightnessLog, type: .info, result)
        }
    }

    // MARK: - Software Gamma

    private func setSoftwareGamma(_ displayID: CGDirectDisplayID, value: Float) {
        if value >= 1.0 {
            CGDisplayRestoreColorSyncSettings()
            softwareGammaValues.removeValue(forKey: displayID)
            for (id, val) in softwareGammaValues {
                let v = CGGammaValue(val)
                CGSetDisplayTransferByFormula(id, 0, v, 1.0, 0, v, 1.0, 0, v, 1.0)
            }
        } else {
            let v = CGGammaValue(value)
            CGSetDisplayTransferByFormula(
                displayID,
                0, v, 1.0,
                0, v, 1.0,
                0, v, 1.0
            )
            softwareGammaValues[displayID] = value
        }
        persistGamma()
    }

    // MARK: - Persistence

    private func persistGamma() {
        let dict = Dictionary(uniqueKeysWithValues: softwareGammaValues.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(dict, forKey: Self.gammaDefaultsKey)
    }

    private func loadPersistedGamma() {
        guard let dict = UserDefaults.standard.dictionary(forKey: Self.gammaDefaultsKey) as? [String: Float] else { return }
        for (key, value) in dict {
            if let displayID = UInt32(key), value < 1.0 {
                softwareGammaValues[displayID] = value
            }
        }
        if !softwareGammaValues.isEmpty {
            Log.info("BrightnessManager: loaded persisted gamma for \(softwareGammaValues.count) display(s)")
        }
    }
}
