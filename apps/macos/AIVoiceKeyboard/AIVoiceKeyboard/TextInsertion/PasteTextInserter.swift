import AppKit
import Carbon.HIToolbox
import Foundation

/// v0.1 inserter: paste via clipboard + Cmd+V.
///
/// Tradeoffs:
/// - Fast to ship and works in many apps.
/// - Mutates clipboard (intentionally kept as transcript in v0.1; user can restore via menu).
final class PasteTextInserter: TextInserter {
  enum PasteInsertError: LocalizedError {
    case emptyText
    case eventSourceUnavailable
    case failedToCreateKeyEvents

    var errorDescription: String? {
      switch self {
      case .emptyText:
        return "Nothing to insert"
      case .eventSourceUnavailable:
        return "Cannot synthesize keyboard events"
      case .failedToCreateKeyEvents:
        return "Failed to send paste shortcut"
      }
    }
  }

  init() {}

  @discardableResult
  func insert(text: String) throws -> TextInsertionMethod {
    // Insert is designed for natural language dictation; we trim leading/trailing whitespace.
    // If we add "code mode" later, we should revisit this.
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw PasteInsertError.emptyText }

    NSLog("[Insert][Paste] inserting via clipboard (length: %d)", trimmed.count)

    let pb = NSPasteboard.general

    // v0.1 behavior: keep the transcript in the clipboard so users can Cmd+V manually
    // even if synthetic Cmd+V is blocked by the OS/app. The app menu offers a
    // "Restore Original Clipboard" action (snapshot managed by AppDelegate).
    pb.clearContents()
    pb.setString(trimmed, forType: .string)
    NSLog("[Insert][Paste] clipboard populated")

    // If Accessibility is not enabled, synthetic Cmd+V is usually blocked by the OS.
    // In that case we intentionally keep the transcript in clipboard and let the user paste manually.
    if !PermissionChecks.status(for: .accessibility).isSatisfied {
      NSLog("[Insert] Accessibility not enabled; skipped synthetic Cmd+V (clipboard populated)")
      return .pasteClipboardOnly
    }

    // Best-effort: if synthetic Cmd+V fails, keep clipboard populated so user can paste manually.
    do {
      NSLog("[Insert][Paste] posting synthetic Cmd+V (best-effort)")
      try postPasteKeyChord()
    } catch {
      NSLog("[Insert] Synthetic Cmd+V failed (%@); clipboard populated for manual paste.", error.localizedDescription)
      return .pasteClipboardOnly
    }

    NSLog("[Insert][Paste] synthetic Cmd+V posted (best-effort)")
    return .paste
  }

  private func postPasteKeyChord() throws {
    let virtualKeyV: CGKeyCode = CGKeyCode(kVK_ANSI_V)

    guard let source = CGEventSource(stateID: .hidSystemState) else {
      throw PasteInsertError.eventSourceUnavailable
    }

    guard let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: false)
    else {
      throw PasteInsertError.failedToCreateKeyEvents
    }

    down.flags = [.maskCommand]
    up.flags = [.maskCommand]

    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
  }
}
