import AppKit
import CoreGraphics

struct DisplayInfo {
    let displayID: CGDirectDisplayID
    let frame: CGRect        // CG coordinates (top-left origin)
    let visibleFrame: CGRect // CG coordinates, excluding menu bar/dock
    let isMain: Bool
    let localizedName: String
}

protocol DisplayManagerDelegate: AnyObject {
    func displayManagerDidDetectChange(_ manager: DisplayManager)
}

final class DisplayManager {
    weak var delegate: DisplayManagerDelegate?

    private(set) var displays: [DisplayInfo] = []

    init() {
        refresh()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func refresh() {
        displays = NSScreen.screens.enumerated().map { index, screen in
            DisplayInfo(
                displayID: screen.displayID,
                frame: screen.cgFrame,
                visibleFrame: screen.cgVisibleFrame,
                isMain: index == 0,
                localizedName: screen.localizedName
            )
        }
    }

    func display(for id: CGDirectDisplayID) -> DisplayInfo? {
        displays.first { $0.displayID == id }
    }

    @objc private func screenParametersDidChange() {
        refresh()
        delegate?.displayManagerDidDetectChange(self)
    }
}
