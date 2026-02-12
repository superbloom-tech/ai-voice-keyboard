import Carbon.HIToolbox
import Foundation

/// Registers global hotkeys (works while other apps are focused) using Carbon APIs.
///
/// Notes:
/// - Does NOT require Accessibility permission (we're not synthesizing input).
/// - Registration can fail if another app already owns the hotkey.
final class GlobalHotKeyCenter {
  enum Action: Sendable {
    case toggleInsert
    case toggleEdit

    var displayName: String {
      switch self {
      case .toggleInsert:
        return "Insert"
      case .toggleEdit:
        return "Edit"
      }
    }
  }

  struct Binding: Sendable {
    var id: UInt32
    var keyCode: UInt32
    var modifiers: UInt32
    var action: Action
  }

  enum RegistrationError: Error, LocalizedError {
    case installHandlerFailed(OSStatus)
    case registerFailed(action: Action, status: OSStatus)

    var errorDescription: String? {
      switch self {
      case .installHandlerFailed(let status):
        return "InstallEventHandler failed (\(status))."
      case .registerFailed(let action, let status) where status == OSStatus(eventHotKeyExistsErr):
        return "\(action.displayName) hotkey already in use (conflict with another app)."
      case .registerFailed(let action, let status):
        return "RegisterEventHotKey failed for \(action.displayName) (\(status))."
      }
    }
  }

  // MARK: - Public

  /// Called on the MainActor when a hotkey fires.
  var onAction: (@MainActor (Action) -> Void)?

  func registerDefaultHotKeys() throws {
    // Keep ids stable so adding/reordering hotkeys won't silently change behavior.
    enum HotKeyID {
      static let insert: UInt32 = 1
      static let edit: UInt32 = 2
    }

    // Default bindings:
    // - Insert: Option+Space
    // - Edit: Option+Shift+Space
    try registerHotKeys([
      Binding(id: HotKeyID.insert, keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), action: .toggleInsert),
      Binding(id: HotKeyID.edit, keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey), action: .toggleEdit),
    ])
  }

  func unregisterAll() {
    for ref in registeredHotKeyRefs.values {
      if let ref {
        UnregisterEventHotKey(ref)
      }
    }
    registeredHotKeyRefs.removeAll()
    actionByID.removeAll()

    if let handler = eventHandler {
      RemoveEventHandler(handler)
      eventHandler = nil
    }
  }

  deinit {
    unregisterAll()
  }

  // MARK: - Private

  // Keep this stable across versions; Carbon uses (signature,id) as the hotkey identity.
  private let signature: OSType = GlobalHotKeyCenter.fourCharCode("AVKB")

  private var eventHandler: EventHandlerRef?
  private var actionByID: [UInt32: Action] = [:]
  private var registeredHotKeyRefs: [UInt32: EventHotKeyRef?] = [:]

  func registerHotKeys(_ bindings: [Binding]) throws {
    // Ensure we don't leak multiple handlers/registrations across retries.
    unregisterAll()

    do {
      let spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
      let status = InstallEventHandler(
        GetApplicationEventTarget(),
        globalHotKeyEventHandler,
        1,
        [spec],
        UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
        &eventHandler
      )
      guard status == noErr else {
        throw RegistrationError.installHandlerFailed(status)
      }

      for binding in bindings {
        let id = binding.id
        actionByID[id] = binding.action

        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var ref: EventHotKeyRef?
        let regStatus = RegisterEventHotKey(
          binding.keyCode,
          binding.modifiers,
          hotKeyID,
          GetApplicationEventTarget(),
          0,
          &ref
        )
        guard regStatus == noErr else {
          throw RegistrationError.registerFailed(action: binding.action, status: regStatus)
        }

        registeredHotKeyRefs[id] = ref
      }
    } catch {
      // Avoid partially-registered hotkeys if any step fails.
      unregisterAll()
      throw error
    }
  }

  fileprivate func handleHotKeyEvent(id: UInt32) {
    guard let action = actionByID[id] else { return }
    Task { @MainActor [weak self] in
      self?.onAction?(action)
    }
  }

  private static func fourCharCode(_ string: String) -> OSType {
    // OSType is big-endian four-char code.
    var result: UInt32 = 0
    for scalar in string.unicodeScalars.prefix(4) {
      result = (result << 8) + UInt32(scalar.value)
    }
    return OSType(result)
  }
}

private func globalHotKeyEventHandler(
  _ nextHandler: EventHandlerCallRef?,
  _ event: EventRef?,
  _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let event else { return OSStatus(eventNotHandledErr) }
  guard let userData else { return OSStatus(eventNotHandledErr) }

  var hotKeyID = EventHotKeyID()
  let status = GetEventParameter(
    event,
    EventParamName(kEventParamDirectObject),
    EventParamType(typeEventHotKeyID),
    nil,
    MemoryLayout<EventHotKeyID>.size,
    nil,
    &hotKeyID
  )
  guard status == noErr else { return status }

  let center = Unmanaged<GlobalHotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
  center.handleHotKeyEvent(id: hotKeyID.id)

  return noErr
}
