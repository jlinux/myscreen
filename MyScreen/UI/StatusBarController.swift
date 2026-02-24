import AppKit
import SwiftUI

final class StatusBarController {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover
    private let viewModel = ControlPanelViewModel()
    private var eventMonitor: Any?

    init() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 500)
        popover.behavior = .transient

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "MyScreen")
            button.action = #selector(togglePopover)
            button.target = self
        }

        let hostingView = NSHostingView(rootView: ControlPanelView(viewModel: viewModel))
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = hostingView
    }

    func bindScreenManager(_ manager: ScreenManager) {
        viewModel.screenManager = manager
        viewModel.refresh()
    }

    func showPermissionGuide(onGranted: @escaping () -> Void) {
        let guideView = PermissionGuideView(onGranted: onGranted)
        let hostingView = NSHostingView(rootView: guideView)
        popover.contentViewController?.view = hostingView
        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startEventMonitor()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            stopEventMonitor()
        } else {
            // Restore control panel view
            let hostingView = NSHostingView(rootView: ControlPanelView(viewModel: viewModel))
            popover.contentViewController?.view = hostingView
            viewModel.refresh()
            showPopover()
        }
    }

    private func startEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.popover.isShown == true {
                self?.popover.performClose(nil)
                self?.stopEventMonitor()
            }
        }
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
