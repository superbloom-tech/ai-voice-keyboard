import AppKit
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
  enum Status: String, CaseIterable {
    case idle
    case recordingInsert
    case recordingEdit
    case processing
    case preview
    case error
  }

  @Published var status: Status = .idle
  @Published var hotKeyErrorMessage: String?
  @Published var permissionWarningMessage: String?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let appState = AppState()
  private let hotKeyCenter = GlobalHotKeyCenter()

  private var statusItem: NSStatusItem?
  private var hotKeyInfoMenuItem: NSMenuItem?
  private var hotKeyErrorMenuItem: NSMenuItem?
  private var permissionWarningMenuItem: NSMenuItem?
  private var cancellables: Set<AnyCancellable> = []

  private lazy var settingsWindowController = SettingsWindowController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.statusItem = statusItem

    let menu = NSMenu()

    // Hotkey info + warning section.
    let hotKeyInfo = NSMenuItem(
      title: "Hotkeys: ⌥Space (Insert), ⌥⇧Space (Edit)",
      action: nil,
      keyEquivalent: ""
    )
    hotKeyInfo.isEnabled = false
    menu.addItem(hotKeyInfo)
    self.hotKeyInfoMenuItem = hotKeyInfo

    let hotKeyError = NSMenuItem(
      title: "Hotkeys error: -",
      action: nil,
      keyEquivalent: ""
    )
    hotKeyError.isEnabled = false
    hotKeyError.isHidden = true
    menu.addItem(hotKeyError)
    self.hotKeyErrorMenuItem = hotKeyError

    let permissionWarning = NSMenuItem(
      title: "Permissions: -",
      action: nil,
      keyEquivalent: ""
    )
    permissionWarning.isEnabled = false
    permissionWarning.isHidden = true
    menu.addItem(permissionWarning)
    self.permissionWarningMenuItem = permissionWarning

    menu.addItem(.separator())

    let toggleInsert = NSMenuItem(
      title: "Toggle Insert Recording",
      action: #selector(toggleInsertRecording),
      keyEquivalent: ""
    )
    toggleInsert.target = self
    menu.addItem(toggleInsert)

    let toggleEdit = NSMenuItem(
      title: "Toggle Edit Recording",
      action: #selector(toggleEditRecording),
      keyEquivalent: ""
    )
    toggleEdit.target = self
    menu.addItem(toggleEdit)

    menu.addItem(.separator())

    for status in AppState.Status.allCases {
      let item = NSMenuItem(
        title: "Set State: \(status.rawValue)",
        action: #selector(setStateFromMenu(_:)),
        keyEquivalent: ""
      )
      item.representedObject = status
      item.target = self
      menu.addItem(item)
    }

    menu.addItem(.separator())

    let settingsItem = NSMenuItem(
      title: "Open Settings…",
      action: #selector(openSettings),
      keyEquivalent: ","
    )
    settingsItem.target = self
    menu.addItem(settingsItem)

    let quitItem = NSMenuItem(
      title: "Quit",
      action: #selector(quit),
      keyEquivalent: "q"
    )
    quitItem.target = self
    menu.addItem(quitItem)

    statusItem.menu = menu

    // Render initial icon.
    updateStatusItemIcon(for: appState.status)

    // Register global hotkeys (works while other apps are focused).
    hotKeyCenter.onAction = { [weak self] action in
      guard let self else { return }
      switch action {
      case .toggleInsert:
        self.toggleInsertRecording()
      case .toggleEdit:
        self.toggleEditRecording()
      }
    }

    do {
      try hotKeyCenter.registerDefaultHotKeys()
    } catch {
      appState.hotKeyErrorMessage = error.localizedDescription
    }

    // Observe state changes.
    appState.$status
      .sink { [weak self] status in
        self?.updateStatusItemIcon(for: status)
      }
      .store(in: &cancellables)

    // Observe hotkey errors (e.g. conflicts) and surface them in the menu.
    appState.$hotKeyErrorMessage
      .sink { [weak self] message in
        guard let self else { return }
        if let message {
          self.hotKeyErrorMenuItem?.title = "Hotkeys error: \(message)"
          self.hotKeyErrorMenuItem?.isHidden = false
          self.hotKeyInfoMenuItem?.title = "Hotkeys: disabled (see error below)"
        } else {
          self.hotKeyErrorMenuItem?.isHidden = true
          self.hotKeyInfoMenuItem?.title = "Hotkeys: ⌥Space (Insert), ⌥⇧Space (Edit)"
        }
      }
      .store(in: &cancellables)

    // Observe permission warnings and surface them in the menu.
    appState.$permissionWarningMessage
      .sink { [weak self] message in
        guard let self else { return }
        if let message {
          self.permissionWarningMenuItem?.title = "Permissions: \(message)"
          self.permissionWarningMenuItem?.isHidden = false
        } else {
          self.permissionWarningMenuItem?.isHidden = true
        }
      }
      .store(in: &cancellables)
  }

  func applicationWillTerminate(_ notification: Notification) {
    hotKeyCenter.unregisterAll()
  }

  // MARK: - Actions

  @objc private func toggleInsertRecording() {
    if appState.status == .recordingInsert {
      appState.permissionWarningMessage = nil
      appState.status = .idle
      return
    }

    Task {
      await ensureMicrophonePermissionOrShowError { [weak self] in
        self?.appState.status = .recordingInsert
      }
    }
  }

  @objc private func toggleEditRecording() {
    if appState.status == .recordingEdit {
      appState.permissionWarningMessage = nil
      appState.status = .idle
      return
    }

    Task {
      await ensureMicrophonePermissionOrShowError { [weak self] in
        self?.appState.status = .recordingEdit
      }
    }
  }

  private func ensureMicrophonePermissionOrShowError(onSuccess: @escaping () -> Void) async {
    // Minimal gating (v0.1): we only require microphone permission to enter a "recording" state.
    // - Speech Recognition will be required once Apple Speech STT is integrated.
    // - Accessibility will be required for cross-app selection read/replace and some automation later.
    let currentStatus = PermissionChecks.status(for: .microphone)

    switch currentStatus {
    case .authorized:
      // Permission already granted, proceed
      appState.permissionWarningMessage = nil
      onSuccess()

    case .notDetermined:
      // Request permission
      let newStatus = await PermissionChecks.request(.microphone)
      if newStatus.isSatisfied {
        appState.permissionWarningMessage = nil
        onSuccess()
      } else {
        appState.status = .error
        appState.permissionWarningMessage = "Microphone required. Open Settings…"
        openSettings()
      }

    case .denied, .restricted, .unknown:
      // Permission denied or restricted, show error
      appState.status = .error
      appState.permissionWarningMessage = "Microphone required. Open Settings…"
      openSettings()
    }
  }

  @objc private func setStateFromMenu(_ sender: NSMenuItem) {
    guard let status = sender.representedObject as? AppState.Status else { return }
    appState.status = status
  }

  @objc private func openSettings() {
    settingsWindowController.show()
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  // MARK: - UI

  private func updateStatusItemIcon(for status: AppState.Status) {
    guard let button = statusItem?.button else { return }

    let image = NSImage(
      systemSymbolName: status.systemSymbolName,
      accessibilityDescription: "AI Voice Keyboard"
    )
    image?.isTemplate = true
    button.image = image
    button.toolTip = "AI Voice Keyboard (\(status.rawValue))"
  }
}

extension AppState.Status {
  var systemSymbolName: String {
    switch self {
    case .idle:
      return "mic"
    case .recordingInsert:
      return "mic.fill"
    case .recordingEdit:
      return "pencil.and.scribble"
    case .processing:
      return "sparkles"
    case .preview:
      return "doc.text.magnifyingglass"
    case .error:
      return "exclamationmark.triangle"
    }
  }
}

// MARK: - Settings Window Controller

@MainActor
final class SettingsWindowController {
  private var window: NSWindow?

  func show() {
    // If window already exists, just bring it to front
    if let existingWindow = window, existingWindow.isVisible {
      existingWindow.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    // Store the original activation policy
    let originalPolicy = NSApp.activationPolicy()

    // Switch to regular app to show the window properly
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)

    // Create the settings window
    let settingsView = SettingsView()
    let hostingController = NSHostingController(rootView: settingsView)

    let window = NSWindow(contentViewController: hostingController)
    window.title = "Settings"
    window.styleMask = [.titled, .closable]
    window.center()
    window.isReleasedWhenClosed = false

    // Switch back to accessory when window closes
    window.delegate = SettingsWindowDelegate(
      onClose: { [weak self] in
        self?.window = nil
        if originalPolicy == .accessory {
          NSApp.setActivationPolicy(.accessory)
        }
      }
    )

    self.window = window
    window.makeKeyAndOrderFront(nil as Any?)
  }
}

private class SettingsWindowDelegate: NSObject, NSWindowDelegate {
  private let onClose: () -> Void

  init(onClose: @escaping () -> Void) {
    self.onClose = onClose
  }

  func windowWillClose(_ notification: Notification) {
    onClose()
  }
}
