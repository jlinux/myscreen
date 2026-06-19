# MyScreen

[中文](README.md)

MyScreen is a native macOS menu bar app that reserves screen-edge areas for selected windows and keeps other windows inside the remaining workspace. It is designed for workflows that need a persistent iPhone Mirroring window, chat window, monitoring panel, reference document, or any other auxiliary window.

## Features

- **Reserved screen areas**: Create reserved areas on the left, right, top, or bottom edge of a display.
- **Window binding**: Pick a specific window from a running app and automatically fit it into a reserved area.
- **Workspace constraints**: Keep other windows inside the remaining work area so they do not cover reserved windows.
- **Multi-display support**: Configure reserved areas independently per display.
- **Multiple reserved areas**: Use up to four edge-based reserved areas on the same display.
- **Draggable dividers**: Resize reserved areas by dragging the divider; changes are saved automatically.
- **Quick hide/show**: Toggle reserved areas with the default global shortcut `⌘⌥M`, or customize it in the control panel.
- **Menu bar control panel**: Runs as a menu bar app without taking space in the Dock.
- **Brightness control**: Adjust display brightness, with software dimming fallback when hardware control is unavailable.
- **Persistent settings**: Layouts, window bindings, and hotkeys are stored locally in `UserDefaults`.

## Use Cases

- Keep an iPhone Mirroring window visible on the side of your Mac display.
- Pin chat, docs, dashboards, or reference windows while coding or working.
- Reserve space for utility windows on an external monitor while keeping the main workspace clean.
- Temporarily hide the reserved area for full-screen-style focus, then restore it with a shortcut.

## Requirements

- macOS 14.0 Sonoma or later
- Xcode 16 or compatible
- Swift 5.10
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

MyScreen requires macOS Accessibility permission so it can read, move, and resize other application windows. It does not collect user data and does not provide screenshot or screen recording features.

## Build and Run

```bash
make generate
make build
make run
```

Common commands:

```bash
make generate   # Generate the Xcode project from project.yml
make build      # Build Debug
make run        # Build Debug and launch the app
make release    # Build Release
make clean      # Remove build artifacts and the generated Xcode project
```

If code signing fails, update `DEVELOPMENT_TEAM` in `Makefile` or `project.yml` to your own Apple Developer Team ID.

## Basic Usage

1. Launch MyScreen.
2. Grant Accessibility permission when macOS prompts you: `System Settings` -> `Privacy & Security` -> `Accessibility`.
3. Click the MyScreen menu bar icon to open the control panel.
4. Select a display and click `+` to add a reserved area.
5. Choose the edge and size, using either percentage or pixels.
6. Bind a running application window to the reserved area.
7. Use `⌘⌥M` or your custom shortcut to hide or show reserved areas.

## Project Layout

```text
MyScreen/
├── main.swift / AppDelegate.swift
├── Core/          # Screen management, window monitoring, layout, hotkeys, brightness
├── Models/        # Configuration, layout, window binding, and reserved-area models
├── UI/            # Menu bar panel, app picker, hotkey recorder, permission guide
├── Utilities/     # Accessibility, window-list, and display-ID helpers
docs/              # PRD, competitive analysis, and release notes
project.yml        # XcodeGen configuration
Makefile           # Common build commands
```

## Implementation

MyScreen is built with Swift, AppKit, and SwiftUI. Window management depends on the macOS Accessibility API; display information comes from `NSScreen` / `CGDisplay`; window changes are tracked through a combination of `AXObserver`, `NSWorkspace` notifications, and `CGWindowList` polling. The app sandbox is disabled because window management, global events, and some display-control capabilities require system-level access.

## Current Limitations

- macOS only; iOS and iPadOS are not supported.
- Does not replace macOS Spaces and does not manage apps in system full-screen mode.
- No automated test suite is included yet.
- Source-based usage is supported; packaging, signing, notarization, and distribution still need polish.

## More Documentation

- [Product Requirements Document](docs/PRD.md)
- [v1.0.1 Release Notes](docs/release-notes-v1.0.1.md)
- [v1.0.0 Release Notes](docs/release-notes-v1.0.0.md)
