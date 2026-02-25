# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MyScreen is a native macOS menu bar application (Swift/AppKit) that lets users permanently reserve screen areas for specific apps while constraining other windows to the remaining work area. Requires macOS 14.0+, sandbox disabled for Accessibility API and hardware access.

## Build Commands

```bash
make generate   # Generate Xcode project from project.yml (xcodegen)
make build      # Debug build (runs generate first)
make run        # Debug build + launch app
make release    # Optimized release build (whole-module optimization)
make clean      # Remove build artifacts and generated .xcodeproj
```

The project uses **xcodegen** — the `.xcodeproj` is generated from `project.yml` and should not be edited directly. No unit tests exist currently.

## Architecture

### Core Orchestration

`ScreenManager` is the central orchestrator. It owns and coordinates all major subsystems:

- **DisplayManager** — Multi-display detection/monitoring, coordinate system conversion (NSScreen bottom-left ↔ CoreGraphics top-left)
- **WindowMonitor** — Triple-strategy window tracking: AXObserver (real-time for bound apps), NSWorkspace notifications (app lifecycle), CGWindowList polling (adaptive 0.5s–3s interval)
- **LayoutEngine** — Geometry calculations for reserved areas, dividers, and work area per display; supports multiple slots with pixel or percentage sizing
- **WorkAreaConstraint** — Confines non-bound windows to the work area via Accessibility API repositioning; debounced (300ms), skips small windows (<150×100)
- **BarrierWindow** — Transparent 8px divider strips; invisible by default, fade-in on hover, draggable for live resizing
- **BrightnessManager** — Three-tier fallback: DisplayServices API → DDC/CI via IOAVService → software gamma
- **HotkeyManager** — Global hotkeys via CGEvent tap at session level

### Data Flow

`AppConfig.shared` (singleton, thread-safe via DispatchQueue) persists per-display `ScreenLayout` objects to UserDefaults as JSON. Each `ScreenLayout` contains multiple `ReservedSlot` instances, each with a `ReservedArea` (edge + size spec) and optional `AppBinding`.

### UI Layer

- **StatusBarController** — NSStatusBar icon + NSPopover hosting the control panel
- **ControlPanelView / ControlPanelViewModel** — SwiftUI control panel for display selection, brightness, slot management
- **BarrierWindow** — AppKit NSWindow subclass with custom mouse tracking and CoreAnimation transitions

### Key Patterns

- **Delegate pattern**: `WindowMonitorDelegate`, `DisplayManagerDelegate`, `BarrierWindowDelegate`
- **Adaptive polling**: WindowMonitor boosts to fast interval on activity, decays to slow when idle
- **Full-screen detection**: Dual method (AXFullScreen attribute + frame comparison); hides barriers during full-screen

### Source Layout

```
MyScreen/
├── main.swift / AppDelegate.swift    # Entry point, accessibility permission flow
├── Core/        # ScreenManager, WindowMonitor, DisplayManager, LayoutEngine,
│                # WorkAreaConstraint, WindowController, HotkeyManager, BrightnessManager
├── Models/      # AppConfig, ScreenLayout, ReservedArea, AppBinding
├── UI/          # StatusBarController, ControlPanelView/ViewModel, BarrierWindow,
│                # PermissionGuideView, AppPickerView, HotkeyRecorderView
└── Utilities/   # AccessibilityHelper, CGWindowListHelper, NSScreen+DisplayID
```

## Important Technical Notes

- **Coordinate systems**: CoreGraphics uses top-left origin; NSScreen uses bottom-left. Conversion happens in `NSScreen+DisplayID.swift`.
- **AXObserver memory**: Uses `Unmanaged<CFTypeRef>` with manual retain/release in observer setup/teardown. Be careful with lifecycle.
- **No sandbox**: App requires accessibility permissions, IOKit access for DDC/CI, and global event taps — sandbox is disabled in entitlements.
- **BrightnessManager** dynamically loads private DisplayServices framework symbols at runtime.
