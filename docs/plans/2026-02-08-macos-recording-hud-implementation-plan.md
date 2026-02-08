# macOS Recording HUD Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** When the app enters a recording state (Insert/Edit), show an always-on-top non-activating HUD with mode + elapsed timer; hide it when recording stops.

**Architecture:** A small `NSPanel` (non-activating, click-through) hosting a SwiftUI view. The HUD controller observes `AppState.status` and toggles visibility + resets the timer per recording session.

**Tech Stack:** AppKit (`NSPanel`) + SwiftUI (`NSHostingController`, `TimelineView`) + Combine.

## Task 1: Add HUD controller + SwiftUI view

**Files:**
- Create: `apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/HUD/RecordingHUDController.swift`
- Modify: `apps/macos/AIVoiceKeyboard/AIVoiceKeyboard.xcodeproj/project.pbxproj` (add new source file)

**Implementation notes:**
- Use `NSPanel` with `.nonactivatingPanel` + `.borderless`, `level = .statusBar` (or `.floating` if needed).
- `ignoresMouseEvents = true` (click-through), `isOpaque = false`, `backgroundColor = .clear`.
- SwiftUI view uses `TimelineView(.periodic...)` to render elapsed time from `startedAt`.
- Position at top-center of `NSScreen.main?.visibleFrame` with a small margin.

**Verification:**
- `xcodebuild -project apps/macos/AIVoiceKeyboard/AIVoiceKeyboard.xcodeproj -scheme AIVoiceKeyboard -configuration Debug -sdk macosx -destination "platform=macOS" build`

## Task 2: Wire HUD to app state transitions

**Files:**
- Modify: `apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/AppDelegate.swift`

**Steps:**
- Add a `RecordingHUDController` instance to `AppDelegate`.
- In the existing `appState.$status` sink, call `hud.update(for: status)`.
- Policy:
  - `.recordingInsert` / `.recordingEdit` => show HUD and set mode; if entering from non-recording, reset `startedAt`.
  - any other state => hide HUD + clear startedAt.

**Verification:**
- Re-run `xcodebuild ... build`

## Task 3: Manual acceptance checks

**Steps:**
- Launch the app.
- Trigger recording (menu item or hotkey): HUD appears, does not steal focus, stays on top.
- Stop recording: HUD disappears.

