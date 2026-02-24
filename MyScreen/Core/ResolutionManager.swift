import CoreGraphics

final class ResolutionManager {
    /// Merged cache: preserves all modes ever seen so HiDPI entries survive mode switches.
    private var modeCache: [CGDirectDisplayID: [String: DisplayMode]] = [:]

    func availableModes(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let cgModes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else {
            return Array(modeCache[displayID]?.values ?? [:].values)
        }

        var cached = modeCache[displayID] ?? [:]
        for cgMode in cgModes {
            let mode = DisplayMode(cgMode: cgMode)
            // Always update with fresh CGDisplayMode reference
            cached[mode.id] = mode
        }
        modeCache[displayID] = cached

        return Array(cached.values)
    }

    func groupedModes(for displayID: CGDirectDisplayID) -> [DisplayModeGroup] {
        let modes = availableModes(for: displayID)
        var grouped: [String: [DisplayMode]] = [:]
        for mode in modes {
            let key = "\(mode.width)x\(mode.height)"
            grouped[key, default: []].append(mode)
        }

        return grouped.map { (_, modes) in
            DisplayModeGroup(width: modes[0].width, height: modes[0].height, modes: modes)
        }
        .sorted { a, b in
            let areaA = a.width * a.height
            let areaB = b.width * b.height
            return areaA > areaB
        }
    }

    func currentMode(for displayID: CGDirectDisplayID) -> DisplayMode? {
        guard let cgMode = CGDisplayCopyDisplayMode(displayID) else { return nil }
        return DisplayMode(cgMode: cgMode)
    }

    @discardableResult
    func setMode(_ mode: DisplayMode, for displayID: CGDirectDisplayID) -> Bool {
        // First try the cached CGDisplayMode reference
        let result = CGDisplaySetDisplayMode(displayID, mode.cgMode, nil)
        if result == .success {
            Log.info("ResolutionManager: switched display \(displayID) to \(mode.dimensionLabel)")
            return true
        }

        // Cached reference may be stale. Query fresh modes and find a match.
        Log.info("ResolutionManager: stale mode reference (error=\(result.rawValue)), trying fresh lookup for \(mode.id)")
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let cgModes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else {
            Log.info("ResolutionManager: CGDisplayCopyAllDisplayModes returned nil")
            return false
        }

        for cgMode in cgModes {
            let fresh = DisplayMode(cgMode: cgMode)
            if fresh.id == mode.id {
                let retryResult = CGDisplaySetDisplayMode(displayID, cgMode, nil)
                if retryResult == .success {
                    // Update cache with the fresh reference
                    modeCache[displayID]?[fresh.id] = fresh
                    Log.info("ResolutionManager: switched display \(displayID) to \(mode.dimensionLabel) (fresh ref)")
                    return true
                }
                Log.info("ResolutionManager: fresh ref also failed, error=\(retryResult.rawValue)")
                return false
            }
        }

        Log.info("ResolutionManager: mode \(mode.id) not found in current mode list — unavailable after mode change")
        return false
    }

    func invalidateCache() {
        modeCache.removeAll()
    }
}
