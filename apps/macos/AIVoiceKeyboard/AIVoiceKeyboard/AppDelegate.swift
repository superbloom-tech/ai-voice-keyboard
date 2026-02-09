import AppKit
import Combine
import SwiftUI
import Dispatch

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
  private enum SettingsKeys {
    static let persistHistoryEnabled = "avkb.persistHistoryEnabled"
  }

  private let appState = AppState()
  private let hotKeyCenter = GlobalHotKeyCenter()
  private var recordingHUD: RecordingHUDController?

  private let historyStore: HistoryStore

  // Insert-only v0.1 pipeline.
  private let inserter: TextInserter = PasteTextInserter()
  private var transcriber: AppleSpeechTranscriber?

  override init() {
    let enabled = UserDefaults.standard.bool(forKey: SettingsKeys.persistHistoryEnabled)
    self.historyStore = HistoryStore(maxEntries: 30, persistenceEnabled: enabled)
    super.init()
  }

  private var statusItem: NSStatusItem?
  private var hotKeyInfoMenuItem: NSMenuItem?
  private var hotKeyErrorMenuItem: NSMenuItem?
  private var permissionWarningMenuItem: NSMenuItem?
  private var historyMenu: NSMenu?

  private var lastClipboardSnapshot: PasteboardSnapshot?

  private var cancellables: Set<AnyCancellable> = []

  private let activationPolicyController = ActivationPolicyController()
  private lazy var settingsWindowController = SettingsWindowController(
    activationPolicyController: activationPolicyController
  )

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    do {
      transcriber = try AppleSpeechTranscriber()
    } catch {
      transcriber = nil
    }

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
#if !DEBUG
    toggleEdit.title = "Toggle Edit Recording (Coming soon)"
    toggleEdit.isEnabled = false
#endif
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

    // Set up a non-activating always-on-top HUD for recording states.
    recordingHUD = RecordingHUDController()

    // Register global hotkeys (works while other apps are focused).
    hotKeyCenter.onAction = { [weak self] action in
      guard let self else { return }
      switch action {
      case .toggleInsert:
        self.toggleInsertRecording()
      case .toggleEdit:
#if DEBUG
        self.toggleEditRecording()
#else
        // Edit is not implemented yet; keep hotkey consistent with the disabled menu item.
        self.appState.permissionWarningMessage = "Edit mode coming soon"
#endif
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
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.rebuildHistoryMenu()
      }
      .store(in: &cancellables)

    // Notifications may be posted from background threads (e.g. future STT/LLM pipeline),
    // so we hop to main before touching AppKit UI or MainActor state.
    NotificationCenter.default
      .publisher(for: .avkbHistoryAppendInsert)
      .compactMap { $0.userInfo?[HistoryNotifications.textKey] as? String }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .receive(on: DispatchQueue.main)
      .sink { [weak self] text in
        self?.historyStore.append(mode: .insert, text: text)
      }
      .store(in: &cancellables)

    NotificationCenter.default
      .publisher(for: .avkbHistoryAppendEdit)
      .compactMap { $0.userInfo?[HistoryNotifications.textKey] as? String }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .receive(on: DispatchQueue.main)
      .sink { [weak self] text in
        self?.historyStore.append(mode: .edit, text: text)
      }
      .store(in: &cancellables)

    NotificationCenter.default
      .publisher(for: UserDefaults.didChangeNotification, object: UserDefaults.standard)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        guard let self else { return }
        let enabled = UserDefaults.standard.bool(forKey: SettingsKeys.persistHistoryEnabled)
        self.historyStore.setPersistenceEnabled(enabled)
      }
      .store(in: &cancellables)

    NotificationCenter.default
      .publisher(for: .avkbHistoryDeletePersistedFile)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        self?.historyStore.deletePersistedFileBestEffort()
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
      appState.status = .processing

      Task { [weak self] in
        guard let self else { return }
        do {
          let text = try await self.stopTranscriptionAndInsert()
          if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.historyStore.append(mode: .insert, text: text)
          }
          self.appState.status = .idle
        } catch {
          // Auto-retry once for intermittent Apple Speech local service failures (1101).
          let ns = error as NSError
          if ns.domain == "kAFAssistantErrorDomain" && ns.code == 1101 {
            do {
              try await Task.sleep(nanoseconds: 600_000_000)
              let text = try await self.stopTranscriptionAndInsert()
              if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.historyStore.append(mode: .insert, text: text)
              }
              self.appState.status = .idle
              return
            } catch {
              // Fall through to the standard error UI.
            }
          }

          self.appState.status = .error
          self.appState.permissionWarningMessage = "Insert failed: \(error.localizedDescription)"
        }
      }
      return
    }

    Task { [weak self] in
      guard let self else { return }
      await self.ensureInsertPermissionsOrShowError { [weak self] in
        guard let self else { return }
        do {
          try self.startTranscription()
          self.appState.status = .recordingInsert
        } catch {
          self.appState.status = .error
          self.appState.permissionWarningMessage = "Insert failed: \(error.localizedDescription)"
        }
      }
    }
  }

  @objc private func toggleEditRecording() {
    if appState.status == .recordingEdit {
      appendPlaceholderHistoryFromClipboard(mode: .edit)
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

  private func ensureInsertPermissionsOrShowError(onSuccess: @escaping () -> Void) async {
    // Insert-only v0.1 requires microphone + speech recognition permissions.
    if PermissionChecks.status(for: .microphone) == .notDetermined {
      _ = await PermissionChecks.request(.microphone)
    }
    if PermissionChecks.status(for: .speechRecognition) == .notDetermined {
      _ = await PermissionChecks.request(.speechRecognition)
    }

    let mic = PermissionChecks.status(for: .microphone)
    let speech = PermissionChecks.status(for: .speechRecognition)

    guard mic.isSatisfied else {
      appState.status = .error
      appState.permissionWarningMessage = "Microphone required. Use “Open Settings…” from the menu bar."
      return
    }

    guard speech.isSatisfied else {
      appState.status = .error
      appState.permissionWarningMessage = "Speech Recognition required. Use “Open Settings…” from the menu bar."
      return
    }

    // Accessibility is required for reliably pasting into other apps via synthetic Cmd+V.
    // If it's not enabled, we still allow recording/transcription but expect a clipboard-only fallback.
    if !PermissionChecks.status(for: .accessibility).isSatisfied {
      appState.permissionWarningMessage = "Accessibility not enabled: will copy to clipboard; enable Accessibility for auto-insert"
    } else {
      appState.permissionWarningMessage = nil
    }

    onSuccess()
  }

  private func ensureMicrophonePermissionOrShowError(onSuccess: @escaping () -> Void) async {
    // Edit mode is still placeholder; keep microphone gating so the state machine remains usable.
    let currentStatus = PermissionChecks.status(for: .microphone)

    switch currentStatus {
    case .authorized:
      appState.permissionWarningMessage = nil
      onSuccess()

    case .notDetermined:
      let newStatus = await PermissionChecks.request(.microphone)
      if newStatus.isSatisfied {
        appState.permissionWarningMessage = nil
        onSuccess()
      } else {
        appState.status = .error
        appState.permissionWarningMessage = "Microphone required. Use “Open Settings…” from the menu bar."
      }

    case .denied, .restricted, .unknown:
      appState.status = .error
      appState.permissionWarningMessage = "Microphone required. Use “Open Settings…” from the menu bar."
    }
  }

  private func appendPlaceholderHistoryFromClipboard(mode: HistoryMode) {
#if DEBUG
    // Developer helper: simulate a transcript by reading clipboard text.
    let pb = NSPasteboard.general
    guard let s = pb.string(forType: .string) else { return }
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    let maxLen = 10_000
    let payload = (trimmed.count > maxLen) ? String(trimmed.prefix(maxLen)) : trimmed
    historyStore.append(mode: mode, text: payload)
#else
    _ = mode
#endif
  }

  private func startTranscription() throws {
    guard let transcriber else {
      throw NSError(domain: "AIVoiceKeyboard", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable"])
    }
    try transcriber.start()
  }

  private func stopTranscriptionAndInsert() async throws -> String {
    guard let transcriber else {
      throw NSError(domain: "AIVoiceKeyboard", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable"])
    }

    let text = try await transcriber.stop(timeoutSeconds: 2.0)

    // Capture a fresh snapshot so the user can restore whatever they had right before this insert.
    // (We intentionally do not auto-restore in v0.1.)
    lastClipboardSnapshot = PasteboardSnapshot.capture(from: .general)
    rebuildHistoryMenu()

    try inserter.insert(text: text)
    return text
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

  @objc private func copyHistoryEntry(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? UUID else { return }
    guard let entry = historyStore.entries.first(where: { $0.id == id }) else { return }

    // Capture a fresh snapshot so Restore maps to the last user clipboard state.
    lastClipboardSnapshot = PasteboardSnapshot.capture(from: .general)

    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(entry.text, forType: .string)

    rebuildHistoryMenu()
  }

  @objc private func restoreClipboard(_ sender: NSMenuItem) {
    guard let snap = lastClipboardSnapshot else { return }

    // Only clear the snapshot if we successfully restore; otherwise keep it so the user can retry.
    if snap.restore(to: .general) {
      lastClipboardSnapshot = nil
      rebuildHistoryMenu()
    } else {
      NSSound.beep()
    }
  }

  @objc private func clearHistory(_ sender: NSMenuItem) {
    historyStore.clear()
  }

  // History append notifications are handled via Combine publishers in applicationDidFinishLaunching
  // to ensure main-thread delivery for AppKit / @MainActor safety.

#if DEBUG
  @objc private func addSampleHistoryEntry(_ sender: NSMenuItem) {
    historyStore.append(mode: .insert, text: "Sample transcript: hello world")
    historyStore.append(mode: .edit, text: "Sample edit result: rewritten text")
  }
#endif

  private func rebuildHistoryMenu() {
    guard let menu = historyMenu else { return }

    menu.removeAllItems()

    if let _ = lastClipboardSnapshot {
      let restore = NSMenuItem(
        title: "Restore Original Clipboard",
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

// MARK: - Settings Window Controller

@MainActor
final class SettingsWindowController {
  private var window: NSWindow?
  private let activationPolicyController: ActivationPolicyController

  init(activationPolicyController: ActivationPolicyController) {
    self.activationPolicyController = activationPolicyController
  }

  func show() {
    // If window already exists, just bring it to front
    if let existingWindow = window, existingWindow.isVisible {
      existingWindow.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    // Switch to regular app to show the window properly, but restore safely when all callers release.
    activationPolicyController.pushRegular()
    NSApp.activate(ignoringOtherApps: true)

    // Create the settings window
    let settingsView = SettingsView()
    let hostingController = NSHostingController(rootView: settingsView)

    let window = NSWindow(contentViewController: hostingController)
    window.title = "Settings"
    window.styleMask = [.titled, .closable]
    window.center()
    window.isReleasedWhenClosed = false

    // Restore activation policy when the window closes.
    window.delegate = SettingsWindowDelegate(
      onClose: { [weak self] in
        self?.window = nil
        self?.activationPolicyController.popRegular()
      }
    )

    self.window = window
    window.makeKeyAndOrderFront(nil as Any?)
  }
}

@MainActor
final class ActivationPolicyController {
  private var regularRequestCount = 0
  private var policyBeforeFirstRegular: NSApplication.ActivationPolicy?

  func pushRegular() {
    if regularRequestCount == 0 {
      policyBeforeFirstRegular = NSApp.activationPolicy()
      NSApp.setActivationPolicy(.regular)
    }
    regularRequestCount += 1
  }

  func popRegular() {
    guard regularRequestCount > 0 else { return }
    regularRequestCount -= 1

    guard regularRequestCount == 0 else { return }
    defer { policyBeforeFirstRegular = nil }

    if policyBeforeFirstRegular == .accessory {
      NSApp.setActivationPolicy(.accessory)
    }
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
  private var persistenceEnabled: Bool

  init(maxEntries: Int, persistenceEnabled: Bool) {
    self.maxEntries = maxEntries
    self.persistenceEnabled = persistenceEnabled

    if persistenceEnabled {
      entries = loadEntriesFromDiskBestEffort()
    }
  }

  func setPersistenceEnabled(_ enabled: Bool) {
    guard enabled != persistenceEnabled else { return }
    persistenceEnabled = enabled

    if enabled {
      // When enabling, merge any previously persisted entries with the current in-memory session.
      let disk = loadEntriesFromDiskBestEffort()
      if !disk.isEmpty {
        entries = (entries + disk)
        if entries.count > maxEntries {
          entries.removeLast(entries.count - maxEntries)
        }
      }
      saveToDiskBestEffort()
    }
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
    deletePersistedFileBestEffort()
  }

  func deletePersistedFileBestEffort() {
    // Best-effort: remove the on-disk file if it exists (even when persistence is off).
    do {
      let url = try historyFileURL()
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
    } catch {
      // If deletion fails, fall back to overwriting the file with an empty array.
      // This must work even when persistenceEnabled == false.
      do {
        let url = try historyFileURL(createDirs: true)
        let data = try JSONEncoder().encode([HistoryEntry]())
        try data.write(to: url, options: [.atomic])
      } catch {
        // Ignore: best-effort only.
      }
    }
  }

  private func loadEntriesFromDiskBestEffort() -> [HistoryEntry] {
    do {
      let url = try historyFileURL()
      guard FileManager.default.fileExists(atPath: url.path) else { return [] }
      let data = try Data(contentsOf: url)
      return try JSONDecoder().decode([HistoryEntry].self, from: data)
    } catch {
      // Best-effort only: never block the app on history IO.
      return []
    }
  }

  private func saveToDiskBestEffort() {
    guard persistenceEnabled else { return }

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

struct HistoryNotifications {
  static let textKey = "text"
}

extension Notification.Name {
  static let avkbHistoryAppendInsert = Notification.Name("avkb.history.append.insert")
  static let avkbHistoryAppendEdit = Notification.Name("avkb.history.append.edit")

  static let avkbHistoryDeletePersistedFile = Notification.Name("avkb.history.persist.deleteFile")
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

  @discardableResult
  func restore(to pasteboard: NSPasteboard) -> Bool {
    pasteboard.clearContents()

    if items.isEmpty {
      return true
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

    return pasteboard.writeObjects(pbItems)
  }
}
