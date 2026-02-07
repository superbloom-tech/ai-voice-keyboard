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
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let appState = AppState()
  private let hotKeyCenter = GlobalHotKeyCenter()

  private var statusItem: NSStatusItem?
  private var hotKeyInfoMenuItem: NSMenuItem?
  private var hotKeyErrorMenuItem: NSMenuItem?
  private var cancellables: Set<AnyCancellable> = []

  private let showSettingsSelector = Selector(("showSettingsWindow:"))

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
  }

  func applicationWillTerminate(_ notification: Notification) {
    hotKeyCenter.unregisterAll()
  }

  // MARK: - Actions

  @objc private func toggleInsertRecording() {
    appState.status = (appState.status == .recordingInsert) ? .idle : .recordingInsert
  }

  @objc private func toggleEditRecording() {
    appState.status = (appState.status == .recordingEdit) ? .idle : .recordingEdit
  }

  @objc private func setStateFromMenu(_ sender: NSMenuItem) {
    guard let status = sender.representedObject as? AppState.Status else { return }
    appState.status = status
  }

  @objc private func openSettings() {
    NSApp.activate(ignoringOtherApps: true)
    // SwiftUI Settings scene can be opened via the standard settings action.
    // We use the responder-chain selector to avoid plumbing a custom settings window controller.
    NSApp.sendAction(showSettingsSelector, to: nil, from: nil)
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
