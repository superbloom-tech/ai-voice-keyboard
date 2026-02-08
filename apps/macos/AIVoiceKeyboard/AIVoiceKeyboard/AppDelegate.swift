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

  private let historyStore = HistoryStore(maxEntries: 30)

  private var statusItem: NSStatusItem?
  private var hotKeyInfoMenuItem: NSMenuItem?
  private var hotKeyErrorMenuItem: NSMenuItem?
  private var permissionWarningMenuItem: NSMenuItem?
  private var historyMenu: NSMenu?

  private var lastClipboardSnapshot: PasteboardSnapshot?

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

    let permissionWarning = NSMenuItem(
      title: "Permissions: -",
      action: nil,
      keyEquivalent: ""
    )
    permissionWarning.isEnabled = false
    permissionWarning.isHidden = true
    menu.addItem(permissionWarning)
    self.permissionWarningMenuItem = permissionWarning

    // History: click an entry to copy to clipboard, then user Cmd+V to paste.
    let historyMenuItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
    let historyMenu = NSMenu()
    historyMenuItem.submenu = historyMenu
    menu.addItem(historyMenuItem)
    self.historyMenu = historyMenu

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

    historyStore.$entries
      .sink { [weak self] _ in
        self?.rebuildHistoryMenu()
      }
      .store(in: &cancellables)

    rebuildHistoryMenu()
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

    guard ensureMicrophonePermissionOrShowError() else { return }

    appState.status = .recordingInsert
  }

  @objc private func toggleEditRecording() {
    if appState.status == .recordingEdit {
      appState.permissionWarningMessage = nil
      appState.status = .idle
      return
    }

    guard ensureMicrophonePermissionOrShowError() else { return }

    appState.status = .recordingEdit
  }

  private func ensureMicrophonePermissionOrShowError() -> Bool {
    // Minimal gating (v0.1): we only require microphone permission to enter a "recording" state.
    // - Speech Recognition will be required once Apple Speech STT is integrated.
    // - Accessibility will be required for cross-app selection read/replace and some automation later.
    guard PermissionChecks.status(for: .microphone).isSatisfied else {
      appState.status = .error
      appState.permissionWarningMessage = "Microphone required. Open Settings…"
      openSettings()
      return false
    }

    appState.permissionWarningMessage = nil
    return true
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

  @objc private func copyHistoryEntry(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? UUID else { return }
    guard let entry = historyStore.entries.first(where: { $0.id == id }) else { return }

    // Keep the original clipboard content until the user explicitly restores it.
    if lastClipboardSnapshot == nil {
      lastClipboardSnapshot = PasteboardSnapshot.capture(from: .general)
    }

    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(entry.text, forType: .string)

    rebuildHistoryMenu()
  }

  @objc private func restoreClipboard(_ sender: NSMenuItem) {
    guard let snap = lastClipboardSnapshot else { return }
    snap.restore(to: .general)
    lastClipboardSnapshot = nil
    rebuildHistoryMenu()
  }

  @objc private func clearHistory(_ sender: NSMenuItem) {
    historyStore.clear()
  }

#if DEBUG
  @objc private func addSampleHistoryEntry(_ sender: NSMenuItem) {
    historyStore.append(mode: .insert, text: "Sample transcript: hello world")
  }
#endif

  private func rebuildHistoryMenu() {
    guard let menu = historyMenu else { return }

    menu.removeAllItems()

    if let _ = lastClipboardSnapshot {
      let restore = NSMenuItem(
        title: "Restore Clipboard",
        action: #selector(restoreClipboard(_:)),
        keyEquivalent: ""
      )
      restore.target = self
      menu.addItem(restore)
      menu.addItem(.separator())
    }

#if DEBUG
    let addSample = NSMenuItem(title: "Dev: Add Sample Entry", action: #selector(addSampleHistoryEntry(_:)), keyEquivalent: "")
    addSample.target = self
    menu.addItem(addSample)
#endif

    let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory(_:)), keyEquivalent: "")
    clear.target = self
    clear.isEnabled = !historyStore.entries.isEmpty
    menu.addItem(clear)

    menu.addItem(.separator())

    if historyStore.entries.isEmpty {
      let empty = NSMenuItem(title: "No history yet", action: nil, keyEquivalent: "")
      empty.isEnabled = false
      menu.addItem(empty)
      return
    }

    for entry in historyStore.entries {
      let title = entry.menuTitle(maxLen: 64)
      let item = NSMenuItem(title: title, action: #selector(copyHistoryEntry(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = entry.id
      menu.addItem(item)
    }
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

// MARK: - History + Clipboard

enum HistoryMode: String, Codable, Sendable {
  case insert
  case edit
}

struct HistoryEntry: Identifiable, Codable, Sendable {
  let id: UUID
  let mode: HistoryMode
  let text: String
  let createdAt: Date

  init(id: UUID = UUID(), mode: HistoryMode, text: String, createdAt: Date = Date()) {
    self.id = id
    self.mode = mode
    self.text = text
    self.createdAt = createdAt
  }

  func menuTitle(maxLen: Int) -> String {
    let prefix = (mode == .insert) ? "Insert" : "Edit"
    let raw = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).first.map(String.init) ?? ""
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let body = trimmed.isEmpty ? "(empty)" : trimmed

    if body.count <= maxLen {
      return "\(prefix): \(body)"
    }
    let cut = body.prefix(max(0, maxLen - 1))
    return "\(prefix): \(cut)…"
  }
}

@MainActor
final class HistoryStore: ObservableObject {
  @Published private(set) var entries: [HistoryEntry] = []

  private let maxEntries: Int

  init(maxEntries: Int) {
    self.maxEntries = maxEntries
    loadFromDisk()
  }

  func append(mode: HistoryMode, text: String) {
    let entry = HistoryEntry(mode: mode, text: text)
    entries.insert(entry, at: 0)
    if entries.count > maxEntries {
      entries.removeLast(entries.count - maxEntries)
    }
    saveToDiskBestEffort()
  }

  func clear() {
    entries.removeAll()
    saveToDiskBestEffort()
  }

  private func loadFromDisk() {
    do {
      let url = try historyFileURL()
      guard FileManager.default.fileExists(atPath: url.path) else { return }
      let data = try Data(contentsOf: url)
      entries = try JSONDecoder().decode([HistoryEntry].self, from: data)
    } catch {
      // Best-effort only: never block the app on history IO.
      entries = []
    }
  }

  private func saveToDiskBestEffort() {
    do {
      let url = try historyFileURL(createDirs: true)
      let data = try JSONEncoder().encode(entries)
      try data.write(to: url, options: [.atomic])
    } catch {
      // Ignore IO failures (sandbox/permissions/disk issues).
    }
  }

  private func historyFileURL(createDirs: Bool = false) throws -> URL {
    let fm = FileManager.default
    let base = try fm.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: createDirs
    )

    let dir = base.appendingPathComponent("AI Voice Keyboard", isDirectory: true)
    if createDirs {
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    return dir.appendingPathComponent("history.json", isDirectory: false)
  }
}

struct PasteboardSnapshot: Sendable {
  struct Item: Sendable {
    var dataByType: [String: Data]
    var stringByType: [String: String]
  }

  var items: [Item]

  static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
    let current = pasteboard.pasteboardItems ?? []
    let items: [Item] = current.map { pbItem in
      var dataByType: [String: Data] = [:]
      var stringByType: [String: String] = [:]
      for t in pbItem.types {
        let key = t.rawValue
        if let data = pbItem.data(forType: t) {
          dataByType[key] = data
        } else if let str = pbItem.string(forType: t) {
          stringByType[key] = str
        }
      }
      return Item(dataByType: dataByType, stringByType: stringByType)
    }

    return PasteboardSnapshot(items: items)
  }

  func restore(to pasteboard: NSPasteboard) {
    pasteboard.clearContents()

    if items.isEmpty {
      return
    }

    let pbItems: [NSPasteboardItem] = items.map { snap in
      let item = NSPasteboardItem()
      for (type, data) in snap.dataByType {
        item.setData(data, forType: .init(type))
      }
      for (type, str) in snap.stringByType {
        item.setString(str, forType: .init(type))
      }
      return item
    }

    _ = pasteboard.writeObjects(pbItems)
  }
}
