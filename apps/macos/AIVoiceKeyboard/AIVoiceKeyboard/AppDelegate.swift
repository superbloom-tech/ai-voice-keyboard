import AppKit
import Combine

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
  private var recordingHUD: RecordingHUDController?
  private var isRequestingMicrophonePermission = false
  private let legacySettingsWindowController = SettingsWindowController()

  private var statusItem: NSStatusItem?
  private var hotKeyInfoMenuItem: NSMenuItem?
  private var hotKeyErrorMenuItem: NSMenuItem?
  private var permissionWarningMenuItem: NSMenuItem?
  private var cancellables: Set<AnyCancellable> = []

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
      // Avoid Cmd+, which macOS treats as the standard "Settings…" shortcut and may route through
      // the SwiftUI Settings scene machinery (which can log warnings for accessory apps).
      keyEquivalent: ""
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
    updateStatusItemTooltip()

    // Set up a non-activating always-on-top HUD for recording states.
    recordingHUD = RecordingHUDController()

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
        guard let self else { return }
        self.updateStatusItemIcon(for: status)
        self.recordingHUD?.update(for: status)
        self.updateStatusItemTooltip()
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
        self.updateStatusItemTooltip()
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
        self.updateStatusItemTooltip()
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

    Task { @MainActor [weak self] in
      guard let self else { return }
      guard await self.ensureMicrophonePermissionOrShowError() else { return }
      self.appState.status = .recordingInsert
    }
  }

  @objc private func toggleEditRecording() {
    if appState.status == .recordingEdit {
      appState.permissionWarningMessage = nil
      appState.status = .idle
      return
    }

    Task { @MainActor [weak self] in
      guard let self else { return }
      guard await self.ensureMicrophonePermissionOrShowError() else { return }
      self.appState.status = .recordingEdit
    }
  }

  private func ensureMicrophonePermissionOrShowError() async -> Bool {
    // Minimal gating (v0.1): we only require microphone permission to enter a "recording" state.
    // - Speech Recognition will be required once Apple Speech STT is integrated.
    // - Accessibility will be required for cross-app selection read/replace and some automation later.
    let status = PermissionChecks.status(for: .microphone)
#if DEBUG
    print("[AIVoiceKeyboard] mic status=\(status.rawValue) activationPolicy=\(NSApp.activationPolicy().rawValue) isActive=\(NSApp.isActive)")
#endif
    if status.isSatisfied {
      appState.permissionWarningMessage = nil
      return true
    }

    // If this is the first time, trigger the macOS permission prompt.
    if status == .notDetermined {
      if isRequestingMicrophonePermission {
        appState.permissionWarningMessage = "Microphone permission prompt is already open."
        return false
      }

      isRequestingMicrophonePermission = true
      appState.permissionWarningMessage = "Microphone permission required. Please approve the macOS prompt…"
      // Accessory (menu bar) apps can fail to present permission prompts unless they temporarily behave
      // like a regular app (frontmost, with activation policy `.regular`).
      let previousPolicy = NSApp.activationPolicy()
      if previousPolicy != .regular {
        NSApp.setActivationPolicy(.regular)
      }
      NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
      let requested = await PermissionChecks.request(.microphone)
      isRequestingMicrophonePermission = false
      if previousPolicy != .regular {
        NSApp.setActivationPolicy(previousPolicy)
      }

      if requested.isSatisfied {
        appState.permissionWarningMessage = nil
        return true
      }
    }

    // If denied/restricted (or user dismissed/denied the prompt), macOS won't show the prompt again.
    appState.status = .error
    appState.permissionWarningMessage = "Microphone required. Enable it in System Settings…"
    openSettings()
    PermissionChecks.openSystemSettings(for: .microphone)
    return false
  }

  @objc private func setStateFromMenu(_ sender: NSMenuItem) {
    guard let status = sender.representedObject as? AppState.Status else { return }
    appState.status = status
  }

  @objc private func openSettings() {
#if DEBUG
    NSLog("[AIVoiceKeyboard] openSettings activationPolicy=%ld isActive=%d", NSApp.activationPolicy().rawValue, NSApp.isActive)
#endif
    if #available(macOS 14.0, *) {
      NotificationCenter.default.post(name: .avkOpenSettingsRequest, object: nil)
    } else {
      legacySettingsWindowController.show()
    }
  }

  // MARK: - Standard Settings actions

  /// Handle the standard macOS "Settings…" menu action (Cmd+,) if it is routed to the responder chain.
  /// This makes it work even when other frameworks try to open a Settings scene.
  @objc func showSettingsWindow(_ sender: Any?) {
    openSettings()
  }

  /// Older naming used by some apps/frameworks.
  @objc func showPreferencesWindow(_ sender: Any?) {
    openSettings()
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
  }

  private func updateStatusItemTooltip() {
    guard let button = statusItem?.button else { return }

    var lines: [String] = ["AI Voice Keyboard (\(appState.status.rawValue))"]

    if let message = appState.permissionWarningMessage {
      lines.append("Permissions: \(message)")
    }

    if let message = appState.hotKeyErrorMessage {
      lines.append("Hotkeys error: \(message)")
    }

    button.toolTip = lines.joined(separator: "\n")
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
