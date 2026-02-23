import AppKit
import ApplicationServices

protocol WindowMonitorDelegate: AnyObject {
    func windowMonitorDidDetectChange(_ monitor: WindowMonitor)
}

/// Triple monitoring strategy:
/// 1. AXObserver for bound app windows (real-time)
/// 2. NSWorkspace notifications for app launch/quit
/// 3. CGWindowList polling (200ms) for all window changes
final class WindowMonitor {
    weak var delegate: WindowMonitorDelegate?

    private var pollTimer: Timer?
    private var observers: [pid_t: AXObserver] = [:]
    private var observerRefcons: [pid_t: UnsafeMutableRawPointer] = [:]
    private var monitoredBundleIDs: Set<String> = []
    private var lastWindowSnapshot: [CGWindowID: CGRect] = [:]

    func start() {
        startPolling()
        startWorkspaceNotifications()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        removeAllObservers()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Monitor a specific app for real-time window changes via AXObserver.
    func monitorApp(bundleIdentifier: String) {
        monitoredBundleIDs.insert(bundleIdentifier)
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        for app in apps {
            addObserver(for: app.processIdentifier)
        }
    }

    func unmonitorApp(bundleIdentifier: String) {
        monitoredBundleIDs.remove(bundleIdentifier)
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        for app in apps {
            removeObserver(for: app.processIdentifier)
        }
    }

    // MARK: - CGWindowList Polling

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.pollWindows()
        }
    }

    private func pollWindows() {
        let currentWindows = CGWindowListHelper.allWindows()
        var currentSnapshot: [CGWindowID: CGRect] = [:]
        for w in currentWindows {
            currentSnapshot[w.windowID] = w.frame
        }

        if currentSnapshot != lastWindowSnapshot {
            lastWindowSnapshot = currentSnapshot
            delegate?.windowMonitorDidDetectChange(self)
        }
    }

    // MARK: - Workspace Notifications

    private func startWorkspaceNotifications() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(appDidLaunch(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appDidTerminate(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appDidActivate(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    @objc private func appDidLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              monitoredBundleIDs.contains(bundleID) else { return }
        // Delay slightly to let the app create its windows
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.addObserver(for: app.processIdentifier)
            guard let self = self else { return }
            self.delegate?.windowMonitorDidDetectChange(self)
        }
    }

    @objc private func appDidTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        removeObserver(for: app.processIdentifier)
        delegate?.windowMonitorDidDetectChange(self)
    }

    @objc private func appDidActivate(_ notification: Notification) {
        delegate?.windowMonitorDidDetectChange(self)
    }

    // MARK: - AXObserver

    private func addObserver(for pid: pid_t) {
        guard observers[pid] == nil else { return }

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon = refcon else { return }
            let monitor = Unmanaged<WindowMonitor>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async { [weak monitor] in
                guard let monitor = monitor else { return }
                monitor.delegate?.windowMonitorDidDetectChange(monitor)
            }
        }

        let result = AXObserverCreate(pid, callback, &observer)
        guard result == .success, let obs = observer else { return }

        let refcon = Unmanaged.passRetained(self).toOpaque()
        let appElement = AXUIElementCreateApplication(pid)

        let notifications: [CFString] = [
            kAXMovedNotification as CFString,
            kAXResizedNotification as CFString,
            kAXWindowCreatedNotification as CFString,
            kAXUIElementDestroyedNotification as CFString,
            kAXFocusedWindowChangedNotification as CFString
        ]

        for notif in notifications {
            AXObserverAddNotification(obs, appElement, notif, refcon)
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(obs),
            .defaultMode
        )

        observers[pid] = obs
        observerRefcons[pid] = refcon
    }

    private func removeObserver(for pid: pid_t) {
        guard let obs = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(obs),
            .defaultMode
        )
        // Release the retained self reference
        if let refcon = observerRefcons.removeValue(forKey: pid) {
            Unmanaged<WindowMonitor>.fromOpaque(refcon).release()
        }
    }

    private func removeAllObservers() {
        for pid in Array(observers.keys) {
            removeObserver(for: pid)
        }
    }
}
