# MyScreen v1.0.1 Release Notes

Release date: 2026-03-20

## Overview

This patch release improves day-to-day stability around window visibility toggling and refreshes the visual identity of MyScreen with a cleaner app icon and matching menu bar icon.

## Highlights

- Updated the app icon to a more macOS-native style
- Added a matching menu bar icon so the app feels more consistent in the top bar
- Kept the menu bar icon wired for template rendering so it adapts correctly to system appearance

## Fixes

- Stabilized the visibility toggle flow so repeated minimize and restore actions do not silently fall out of sync

## Recommended Verification

- Launch `MyScreen` from `/Applications/MyScreen.app` and confirm the new app icon appears in Finder, Dock, and Launchpad
- Check the menu bar icon in both light and dark appearances
- Toggle minimize and restore repeatedly on a bound window and confirm the reserved-area behavior stays active

## Notes

- This release is intended as a patch on top of `v1.0.0`
- The release package installed locally was built from the same code included in this tag
