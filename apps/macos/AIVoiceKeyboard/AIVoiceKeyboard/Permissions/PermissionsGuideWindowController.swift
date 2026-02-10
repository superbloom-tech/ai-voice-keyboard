import AppKit
import SwiftUI

@MainActor
final class PermissionsGuideWindowController {
  private var window: NSWindow?

  private let activationPolicyController: ActivationPolicyController

  init(activationPolicyController: ActivationPolicyController) {
    self.activationPolicyController = activationPolicyController
  }

  func show() {
    // If window already exists, just bring it to front.
    if let existingWindow = window, existingWindow.isVisible {
      existingWindow.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    // Switch to regular app to show the window properly, but restore safely when all callers release.
    activationPolicyController.pushRegular()
    NSApp.activate(ignoringOtherApps: true)

    // Create the guide window.
    let hostingController = NSHostingController(
      rootView: PermissionsGuideView(onDone: { [weak self] in
        self?.window?.performClose(nil)
      })
    )

    let window = NSWindow(contentViewController: hostingController)
    window.title = NSLocalizedString("permissions_guide.window_title", comment: "")
    window.styleMask = [.titled, .closable]
    window.center()
    window.isReleasedWhenClosed = false

    // Restore activation policy when the window closes.
    window.delegate = PermissionsGuideWindowDelegate(onClose: { [weak self] in
      self?.window = nil
      self?.activationPolicyController.popRegular()
    })

    self.window = window
    window.makeKeyAndOrderFront(nil as Any?)
  }
}

private final class PermissionsGuideWindowDelegate: NSObject, NSWindowDelegate {
  private let onClose: () -> Void

  init(onClose: @escaping () -> Void) {
    self.onClose = onClose
  }

  func windowWillClose(_ notification: Notification) {
    onClose()
  }
}
