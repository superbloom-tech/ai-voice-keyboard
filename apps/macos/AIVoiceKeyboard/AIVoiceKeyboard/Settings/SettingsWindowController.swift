import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
  private var window: NSWindow?
  private var previousActivationPolicy: NSApplication.ActivationPolicy?

  var isShowing: Bool { window != nil }

  func show() {
    if let window {
#if DEBUG
      print("[AIVoiceKeyboard] SettingsWindowController.show reuse window policy=\(NSApp.activationPolicy().rawValue)")
#endif
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      return
    }

    // Menu bar (LSUIElement) apps often run with `.accessory` activation policy, which can prevent
    // regular windows from showing/activating reliably. Temporarily switch to `.regular` while
    // the settings window is open, then restore on close.
    let currentPolicy = NSApp.activationPolicy()
    previousActivationPolicy = currentPolicy
    if currentPolicy != .regular {
      NSApp.setActivationPolicy(.regular)
    }
#if DEBUG
    print("[AIVoiceKeyboard] SettingsWindowController.show create window policy(from)=\(currentPolicy.rawValue) policy(now)=\(NSApp.activationPolicy().rawValue)")
#endif

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
      if let previousActivationPolicy {
        NSApp.setActivationPolicy(previousActivationPolicy)
        self.previousActivationPolicy = nil
      }
    }
  }
}
