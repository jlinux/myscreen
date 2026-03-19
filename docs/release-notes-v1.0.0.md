# MyScreen v1.0.0 Release Notes

Release date: 2026-03-19

## Overview

This release makes MyScreen much safer for everyday use on multi-display setups and upgrades app binding from app-level behavior to window-level behavior.

## Highlights

- Added window-specific binding instead of only binding by app
- Improved the picker flow so rebinding defaults back to the original app
- Added clearer binding status badges and copy in the control panel
- Auto-refreshes invalid binding state when the target window disappears or returns
- Unified coordinate conversion paths used by screen, barrier, and window placement logic

## Fixes

- Fixed size conversion issues between percent and pixel modes
- Prevented duplicate edge assignment for reserved areas
- Synced monitored bundle IDs with the latest binding configuration
- Limited work-area constraints to the correct display instead of affecting windows on other displays
- Fixed secondary-display top offset caused by incorrect coordinate conversion baseline
- Improved startup behavior for the menu bar app by setting accessory activation policy

## Behavior Changes

- Bound windows are now matched using window metadata such as title, identifier, subrole, and last known frame
- Missing bindings are surfaced directly in the UI and can be rebound from the affected slot
- Work-area clamping now keeps the full window frame inside the valid region instead of cropping edge by edge

## Recommended Verification

- Create different reserved areas on the main display and a secondary display and confirm they stay isolated
- Bind a specific window, close it, and confirm the slot shows a missing-binding state
- Reopen or rebind that window and confirm the status recovers automatically
- Toggle reserved areas on and off and confirm the bound window returns to the expected region

## Known Follow-up Areas

- More regression coverage for mixed vertical display layouts
- Packaging, signing, notarization, and end-user distribution assets
- Additional UI polish for secondary-display debugging and status feedback
