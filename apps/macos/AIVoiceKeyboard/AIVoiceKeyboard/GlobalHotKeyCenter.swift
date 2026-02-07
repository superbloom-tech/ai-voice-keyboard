import Carbon.HIToolbox
import Foundation

/// Registers global hotkeys (works while other apps are focused) using Carbon APIs.
///
/// Notes:
/// - Does NOT require Accessibility permission (we're not synthesizing input).
/// - Registration can fail if another app already owns the hotkey.
final class GlobalHotKeyCenter {
  enum Action {
    case toggleInsert
    case toggleEdit
  }

  struct Binding: Sendable {
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
      case .registerFailed(_, let status) where status == OSStatus(eventHotKeyExistsErr):
        return "Hotkey already in use (conflict with another app)."
      case .registerFailed(let action, let status):
        return "RegisterEventHotKey failed for \(action) (\(status))."
      }
    }
  }

  // MARK: - Public

  /// Called on the main thread when a hotkey fires.
  var onAction: ((Action) -> Void)?

  func registerDefaultHotKeys() throws {
    // Default bindings:
    // - Insert: Option+Space
    // - Edit: Option+Shift+Space
    try registerHotKeys([
      Binding(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), action: .toggleInsert),
      Binding(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey), action: .toggleEdit),
    ])
  }

  func unregisterAll() {
    for ref in registeredHotKeyRefs.values {
      if let ref {
        UnregisterEventHotKey(ref)
      }
    }
    registeredHotKeyRefs.removeAll()

    if let handler = eventHandler {
      RemoveEventHandler(handler)
      eventHandler = nil
    }
  }

  deinit {
    unregisterAll()
  }

  // MARK: - Private

  private let signature: OSType = GlobalHotKeyCenter.fourCharCode("AVKB")

  private var eventHandler: EventHandlerRef?
  private var actionByID: [UInt32: Action] = [:]
  private var registeredHotKeyRefs: [UInt32: EventHotKeyRef?] = [:]

  private func registerHotKeys(_ bindings: [Binding]) throws {
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

      for (idx, binding) in bindings.enumerated() {
        let id = UInt32(idx + 1)
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
    DispatchQueue.main.async { [weak self] in
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
