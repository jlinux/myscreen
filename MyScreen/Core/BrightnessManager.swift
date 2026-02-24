import Foundation
import CoreGraphics
import os.log

private let brightnessLog = OSLog(subsystem: "com.myscreen.app", category: "Brightness")

// MARK: - Control Method

enum BrightnessControlMethod {
    case displayServices
    case softwareGamma
    case unavailable
}

// MARK: - BrightnessManager

final class BrightnessManager {
    static let shared = BrightnessManager()

    // DisplayServices private framework function signatures
    // bool DisplayServicesCanChangeBrightness(CGDirectDisplayID)
    // int DisplayServicesGetBrightness(CGDirectDisplayID, float *)
    // int DisplayServicesSetBrightness(CGDirectDisplayID, float)
    private typealias CanChangeBrightnessFn = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private var canChangeBrightness: CanChangeBrightnessFn?
    private var dsGetBrightness: GetBrightnessFn?
    private var dsSetBrightness: SetBrightnessFn?

    private var methodCache: [CGDirectDisplayID: BrightnessControlMethod] = [:]

    /// Tracks which displays have active software gamma adjustments and their brightness values.
    private var softwareGammaValues: [CGDirectDisplayID: Float] = [:]

    private static let gammaDefaultsKey = "SoftwareGammaBrightness"

    private init() {
        loadDisplayServices()
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
            dsGetBrightness = unsafeBitCast(sym, to: GetBrightnessFn.self)
        }
        if let sym = dlsym(handle, "DisplayServicesSetBrightness") {
            dsSetBrightness = unsafeBitCast(sym, to: SetBrightnessFn.self)
        }

        Log.info("BrightnessManager: DisplayServices loaded — get=\(dsGetBrightness != nil) set=\(dsSetBrightness != nil) canChange=\(canChangeBrightness != nil)")
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
        case .softwareGamma:
            setSoftwareGamma(displayID, value: clamped)
        case .unavailable:
            break
        }
    }

    func invalidateCache() {
        methodCache.removeAll()
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
        // Try DisplayServices (works on both Intel and Apple Silicon)
        if let getFn = dsGetBrightness {
            var brightness: Float = -1
            let result = getFn(displayID, &brightness)
            os_log("DisplayServices probe displayID=%u result=%d brightness=%f", log: brightnessLog, type: .info, displayID, result, brightness)
            if result == 0 && brightness >= 0.0 && brightness <= 1.0 {
                // Also check if we can actually change brightness
                if let canChange = canChangeBrightness {
                    let changeable = canChange(displayID)
                    os_log("DisplayServices canChange=%d for displayID=%u", log: brightnessLog, type: .info, changeable ? 1 : 0, displayID)
                    if changeable {
                        return .displayServices
                    }
                } else {
                    // If canChange is not available, assume we can if get succeeded
                    return .displayServices
                }
            }
        }

        // Fallback: Software Gamma — always available
        return .softwareGamma
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

    // MARK: - Software Gamma

    private func setSoftwareGamma(_ displayID: CGDirectDisplayID, value: Float) {
        if value >= 1.0 {
            // Restore to normal — no need to keep gamma override
            CGDisplayRestoreColorSyncSettings()
            softwareGammaValues.removeValue(forKey: displayID)
            // Reapply other displays' gamma
            for (id, val) in softwareGammaValues {
                let v = CGGammaValue(val)
                CGSetDisplayTransferByFormula(id, 0, v, 1.0, 0, v, 1.0, 0, v, 1.0)
            }
        } else {
            let v = CGGammaValue(value)
            CGSetDisplayTransferByFormula(
                displayID,
                0, v, 1.0,  // red: min, max, gamma
                0, v, 1.0,  // green
                0, v, 1.0   // blue
            )
            softwareGammaValues[displayID] = value
        }
        persistGamma()
    }

    // MARK: - Persistence

    private func persistGamma() {
        // CGDirectDisplayID is UInt32; store as [String: Float] for UserDefaults
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
