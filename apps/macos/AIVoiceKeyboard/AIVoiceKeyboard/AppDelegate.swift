import AppKit
import Combine

extension Notification.Name {
  static let avkToggleInsertRecording = Notification.Name("avk.toggleInsertRecording")
  static let avkToggleEditRecording = Notification.Name("avk.toggleEditRecording")
  static let avkQuitRequest = Notification.Name("avk.quitRequest")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let appModel = AppModel.shared
  private let hotKeyCenter = GlobalHotKeyCenter()
  private var recordingHUD: RecordingHUDController?
  private var isRequestingMicrophonePermission = false
  private let legacySettingsWindowController = LegacySettingsWindowController()

  private var cancellables: Set<AnyCancellable> = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    // Set up a non-activating always-on-top HUD for recording states.
    recordingHUD = RecordingHUDController()

    // SwiftUI `MenuBarExtra` triggers actions via notifications (so we can keep AppKit/logic here).
    NotificationCenter.default.addObserver(
      forName: .avkToggleInsertRecording,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.toggleInsertRecording()
    }
    NotificationCenter.default.addObserver(
      forName: .avkToggleEditRecording,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.toggleEditRecording()
    }
    NotificationCenter.default.addObserver(
      forName: .avkQuitRequest,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.quit()
    }

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
      appModel.hotKeyErrorMessage = error.localizedDescription
    }

    // Observe state changes.
    appModel.$status
      .sink { [weak self] status in
        guard let self else { return }
        self.recordingHUD?.update(for: status)
      }
      .store(in: &cancellables)
  }

  func applicationWillTerminate(_ notification: Notification) {
    hotKeyCenter.unregisterAll()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Actions

  @objc private func toggleInsertRecording() {
    if appModel.status == .recordingInsert {
      appModel.permissionWarningMessage = nil
      appModel.status = .idle
      return
    }

    Task { @MainActor [weak self] in
      guard let self else { return }
      guard await self.ensureMicrophonePermissionOrShowError() else { return }
      self.appModel.status = .recordingInsert
    }
  }

  @objc private func toggleEditRecording() {
    if appModel.status == .recordingEdit {
      appModel.permissionWarningMessage = nil
      appModel.status = .idle
      return
    }

    Task { @MainActor [weak self] in
      guard let self else { return }
      guard await self.ensureMicrophonePermissionOrShowError() else { return }
      self.appModel.status = .recordingEdit
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
      appModel.permissionWarningMessage = nil
      return true
    }

    // If this is the first time, trigger the macOS permission prompt.
    if status == .notDetermined {
      if isRequestingMicrophonePermission {
        appModel.permissionWarningMessage = "Microphone permission prompt is already open."
        return false
      }

      isRequestingMicrophonePermission = true
      appModel.permissionWarningMessage = "Microphone permission required. Please approve the macOS prompt…"
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
        appModel.permissionWarningMessage = nil
        return true
      }
    }

    // If denied/restricted (or user dismissed/denied the prompt), macOS won't show the prompt again.
    appModel.status = .error
    appModel.permissionWarningMessage = "Microphone required. Enable it in System Settings…"
    openSettings()
    PermissionChecks.openSystemSettings(for: .microphone)
    return false
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

  @objc private func quit() {
    NSApp.terminate(nil)
  }
}
