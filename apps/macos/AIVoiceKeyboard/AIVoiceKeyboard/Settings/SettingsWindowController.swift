import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
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

    // Keep size consistent with SettingsView default.
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
