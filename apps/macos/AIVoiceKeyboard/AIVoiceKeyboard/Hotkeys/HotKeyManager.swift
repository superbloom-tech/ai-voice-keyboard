import Carbon.HIToolbox
import AppKit
import Combine
import Foundation

/// Owns global hotkey registration and persists the active configuration.
///
/// Important: We must keep old hotkeys active when applying a new config fails (e.g. conflicts),
/// so `apply` re-registers the last known-good configuration on failure.
@MainActor
final class HotKeyManager: ObservableObject {
  enum HotKeyApplyError: Error, LocalizedError {
    case invalidConfig(String)
    case registrationFailed(String)

    var errorDescription: String? {
      switch self {
      case .invalidConfig(let message):
        return message
      case .registrationFailed(let message):
        return message
      }
    }
  }

  @Published private(set) var configuration: HotKeyConfiguration

  private let center: GlobalHotKeyCenter
  private var activeConfiguration: HotKeyConfiguration

  init(center: GlobalHotKeyCenter) {
    self.center = center
    let cfg = HotKeyConfigurationStore.load()
    self.configuration = cfg
    self.activeConfiguration = cfg
  }

  func start() throws {
    do {
      try register(configuration: configuration)
      activeConfiguration = configuration
    } catch {
      // Best-effort fallback: default hotkeys.
      let fallback = HotKeyConfiguration.default
      do {
        try register(configuration: fallback)
        activeConfiguration = fallback
        configuration = fallback
      } catch {
        // If even defaults can't be registered (conflict), leave hotkeys unregistered.
        throw error
      }
    }
  }

  func resetToDefaults() throws {
    try apply(.default)
  }

  func apply(_ newConfig: HotKeyConfiguration) throws {
    if let message = newConfig.validate() {
      throw HotKeyApplyError.invalidConfig(message)
    }

    do {
      try register(configuration: newConfig)
      activeConfiguration = newConfig
      configuration = newConfig
      HotKeyConfigurationStore.save(newConfig)
    } catch {
      // Keep old hotkeys active.
      try? register(configuration: activeConfiguration)
      throw HotKeyApplyError.registrationFailed(error.localizedDescription)
    }
  }

  func displayString(for action: GlobalHotKeyCenter.Action) -> String {
    switch action {
    case .toggleInsert:
      return configuration.insert.displayString
    case .toggleEdit:
      return configuration.edit.displayString
    }
  }

  // MARK: - Private

  private func register(configuration: HotKeyConfiguration) throws {
    // Keep ids stable so adding/reordering hotkeys won't silently change behavior.
    enum HotKeyID {
      static let insert: UInt32 = 1
      static let edit: UInt32 = 2
    }

    try center.registerHotKeys([
      GlobalHotKeyCenter.Binding(
        id: HotKeyID.insert,
        keyCode: configuration.insert.keyCode,
        modifiers: configuration.insert.modifiers,
        action: .toggleInsert
      ),
      GlobalHotKeyCenter.Binding(
        id: HotKeyID.edit,
        keyCode: configuration.edit.keyCode,
        modifiers: configuration.edit.modifiers,
        action: .toggleEdit
      ),
    ])
  }
}

extension HotKey {
  static func modifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var m: UInt32 = 0
    if flags.contains(.control) { m |= UInt32(controlKey) }
    if flags.contains(.option) { m |= UInt32(optionKey) }
    if flags.contains(.shift) { m |= UInt32(shiftKey) }
    if flags.contains(.command) { m |= UInt32(cmdKey) }
    return m
  }
}
