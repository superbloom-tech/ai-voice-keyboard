import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
  enum Status: String {
    case idle
    case recordingInsert
    case recordingEdit
    case processing
    case preview
    case error
  }

  @Published var status: Status = .idle
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let appState = AppState()

  private var statusItem: NSStatusItem?
  private var cancellables: Set<AnyCancellable> = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.statusItem = statusItem

    let menu = NSMenu()

    menu.addItem(NSMenuItem(
      title: "Toggle Insert Recording",
      action: #selector(toggleInsertRecording),
      keyEquivalent: ""
    ))

    menu.addItem(NSMenuItem(
      title: "Toggle Edit Recording",
      action: #selector(toggleEditRecording),
      keyEquivalent: ""
    ))

    menu.addItem(.separator())

    for status in AppState.Status.allCasesForMenu {
      let item = NSMenuItem(
        title: "Set State: \(status.rawValue)",
        action: #selector(setStateFromMenu(_:)),
        keyEquivalent: ""
      )
      item.representedObject = status
      menu.addItem(item)
    }

    menu.addItem(.separator())

    menu.addItem(NSMenuItem(
      title: "Open Settings…",
      action: #selector(openSettings),
      keyEquivalent: ","
    ))

    menu.addItem(NSMenuItem(
      title: "Quit",
      action: #selector(quit),
      keyEquivalent: "q"
    ))

    statusItem.menu = menu

    // Render initial icon.
    updateStatusItemIcon(for: appState.status)

    // Observe state changes.
    appState.$status
      .sink { [weak self] status in
        self?.updateStatusItemIcon(for: status)
      }
      .store(in: &cancellables)
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
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  // MARK: - UI

  private func updateStatusItemIcon(for status: AppState.Status) {
    guard let button = statusItem?.button else { return }

    let symbolName: String
    switch status {
    case .idle:
      symbolName = "mic"
    case .recordingInsert:
      symbolName = "mic.fill"
    case .recordingEdit:
      symbolName = "pencil.and.scribble"
    case .processing:
      symbolName = "sparkles"
    case .preview:
      symbolName = "doc.text.magnifyingglass"
    case .error:
      symbolName = "exclamationmark.triangle"
    }

    let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AI Voice Keyboard")
    image?.isTemplate = true
    button.image = image
    button.toolTip = "AI Voice Keyboard (\(status.rawValue))"
  }
}

extension AppState.Status {
  static var allCasesForMenu: [AppState.Status] {
    [.idle, .recordingInsert, .recordingEdit, .processing, .preview, .error]
  }
}
