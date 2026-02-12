import Carbon.HIToolbox
import Foundation

/// A persistable global hotkey binding based on Carbon key codes + modifier flags.
///
/// We keep the stored representation Carbon-native because `RegisterEventHotKey` uses these values directly.
struct HotKey: Codable, Hashable, Sendable {
  var keyCode: UInt32
  var modifiers: UInt32

  static let `defaultInsert` = HotKey(
    keyCode: UInt32(kVK_Space),
    modifiers: UInt32(optionKey)
  )

  static let `defaultEdit` = HotKey(
    keyCode: UInt32(kVK_Space),
    modifiers: UInt32(optionKey | shiftKey)
  )

  /// A human-readable string (e.g. "⌥Space", "⌥⇧Space").
  var displayString: String {
    "\(modifierSymbols)\(keyName)"
  }

  /// A concise preview for logging/debugging (ASCII-only).
  var debugString: String {
    "keyCode=\(keyCode) modifiers=\(modifiers)"
  }

  /// Best-effort validation for end-user safety.
  ///
  /// We disallow "no modifiers" and "shift-only" because global hotkeys without a strong modifier
  /// tend to conflict with typing and system shortcuts.
  func validate() -> String? {
    let hasCommand = (modifiers & UInt32(cmdKey)) != 0
    let hasOption = (modifiers & UInt32(optionKey)) != 0
    let hasControl = (modifiers & UInt32(controlKey)) != 0
    let hasShift = (modifiers & UInt32(shiftKey)) != 0

    let hasStrongModifier = hasCommand || hasOption || hasControl
    if !hasStrongModifier {
      if hasShift {
        return NSLocalizedString("settings.hotkeys.error.invalid.shift_only", comment: "")
      }
      return NSLocalizedString("settings.hotkeys.error.invalid.no_modifier", comment: "")
    }

    return nil
  }

  // MARK: - Helpers

  private var modifierSymbols: String {
    var s = ""
    if (modifiers & UInt32(controlKey)) != 0 { s += "⌃" }
    if (modifiers & UInt32(optionKey)) != 0 { s += "⌥" }
    if (modifiers & UInt32(shiftKey)) != 0 { s += "⇧" }
    if (modifiers & UInt32(cmdKey)) != 0 { s += "⌘" }
    return s
  }

  private var keyName: String {
    switch keyCode {
    case UInt32(kVK_Space): return "Space"
    case UInt32(kVK_Return): return "Return"
    case UInt32(kVK_Tab): return "Tab"
    case UInt32(kVK_Escape): return "Esc"
    case UInt32(kVK_Delete): return "Delete"
    case UInt32(kVK_ForwardDelete): return "ForwardDelete"

    case UInt32(kVK_LeftArrow): return "←"
    case UInt32(kVK_RightArrow): return "→"
    case UInt32(kVK_UpArrow): return "↑"
    case UInt32(kVK_DownArrow): return "↓"

    case UInt32(kVK_Home): return "Home"
    case UInt32(kVK_End): return "End"
    case UInt32(kVK_PageUp): return "PageUp"
    case UInt32(kVK_PageDown): return "PageDown"

    case UInt32(kVK_F1): return "F1"
    case UInt32(kVK_F2): return "F2"
    case UInt32(kVK_F3): return "F3"
    case UInt32(kVK_F4): return "F4"
    case UInt32(kVK_F5): return "F5"
    case UInt32(kVK_F6): return "F6"
    case UInt32(kVK_F7): return "F7"
    case UInt32(kVK_F8): return "F8"
    case UInt32(kVK_F9): return "F9"
    case UInt32(kVK_F10): return "F10"
    case UInt32(kVK_F11): return "F11"
    case UInt32(kVK_F12): return "F12"

    case UInt32(kVK_ANSI_A): return "A"
    case UInt32(kVK_ANSI_B): return "B"
    case UInt32(kVK_ANSI_C): return "C"
    case UInt32(kVK_ANSI_D): return "D"
    case UInt32(kVK_ANSI_E): return "E"
    case UInt32(kVK_ANSI_F): return "F"
    case UInt32(kVK_ANSI_G): return "G"
    case UInt32(kVK_ANSI_H): return "H"
    case UInt32(kVK_ANSI_I): return "I"
    case UInt32(kVK_ANSI_J): return "J"
    case UInt32(kVK_ANSI_K): return "K"
    case UInt32(kVK_ANSI_L): return "L"
    case UInt32(kVK_ANSI_M): return "M"
    case UInt32(kVK_ANSI_N): return "N"
    case UInt32(kVK_ANSI_O): return "O"
    case UInt32(kVK_ANSI_P): return "P"
    case UInt32(kVK_ANSI_Q): return "Q"
    case UInt32(kVK_ANSI_R): return "R"
    case UInt32(kVK_ANSI_S): return "S"
    case UInt32(kVK_ANSI_T): return "T"
    case UInt32(kVK_ANSI_U): return "U"
    case UInt32(kVK_ANSI_V): return "V"
    case UInt32(kVK_ANSI_W): return "W"
    case UInt32(kVK_ANSI_X): return "X"
    case UInt32(kVK_ANSI_Y): return "Y"
    case UInt32(kVK_ANSI_Z): return "Z"

    case UInt32(kVK_ANSI_0): return "0"
    case UInt32(kVK_ANSI_1): return "1"
    case UInt32(kVK_ANSI_2): return "2"
    case UInt32(kVK_ANSI_3): return "3"
    case UInt32(kVK_ANSI_4): return "4"
    case UInt32(kVK_ANSI_5): return "5"
    case UInt32(kVK_ANSI_6): return "6"
    case UInt32(kVK_ANSI_7): return "7"
    case UInt32(kVK_ANSI_8): return "8"
    case UInt32(kVK_ANSI_9): return "9"

    default:
      return "KeyCode\(keyCode)"
    }
  }
}

struct HotKeyConfiguration: Codable, Equatable, Sendable {
  var insert: HotKey
  var edit: HotKey

  static let `default` = HotKeyConfiguration(insert: .defaultInsert, edit: .defaultEdit)

  func validate() -> String? {
    if insert == edit {
      return NSLocalizedString("settings.hotkeys.error.conflict.insert_edit_same", comment: "")
    }
    if let m = insert.validate() { return m }
    if let m = edit.validate() { return m }
    return nil
  }
}

enum HotKeyConfigurationStore {
  private static let userDefaultsKey = "avkb.hotkeys.configuration"

  static func load() -> HotKeyConfiguration {
    guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
      return .default
    }

    do {
      return try JSONDecoder().decode(HotKeyConfiguration.self, from: data)
    } catch {
      NSLog("[Hotkeys] Failed to decode saved hotkey config; falling back to default. Error: %@", error.localizedDescription)
      return .default
    }
  }

  static func save(_ config: HotKeyConfiguration) {
    do {
      let data = try JSONEncoder().encode(config)
      UserDefaults.standard.set(data, forKey: userDefaultsKey)
    } catch {
      NSLog("[Hotkeys] Failed to encode hotkey config: %@", error.localizedDescription)
    }
  }
}

