import AppKit
import SwiftUI

/// Pre-macOS 14 fallback (no `openSettings` env action).
@MainActor
final class LegacySettingsWindowController: NSObject, NSWindowDelegate {
  private var window: NSWindow?

  func show() {
    if let window {
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      return
    }

    let controller = NSHostingController(rootView: SettingsView())

    let window = NSWindow(contentViewController: controller)
    window.title = "Settings"
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.isReleasedWhenClosed = false
    window.delegate = self

    window.setContentSize(NSSize(width: 520, height: 320))
    window.center()

    self.window = window

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    guard let closed = notification.object as? NSWindow else { return }
    if closed == window {
      window = nil
    }
  }
}

