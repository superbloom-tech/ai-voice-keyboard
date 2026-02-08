import AppKit
import Foundation

protocol TextInserter {
  func insert(text: String) throws
}

/// Inserts text into the currently focused app by writing the clipboard and sending Cmd+V.
///
/// This is intentionally a v0.1 implementation: fast to ship, but not as robust as AX insertion.
final class PasteTextInserter: TextInserter {
  enum InsertError: LocalizedError {
    case emptyText
    case failedToCreateEvents

    var errorDescription: String? {
      switch self {
      case .emptyText:
        return "Nothing to insert"
      case .failedToCreateEvents:
        return "Failed to synthesize paste shortcut"
      }
    }
  }

  func insert(text: String) throws {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw InsertError.emptyText }

    // Snapshot clipboard so we can restore it after the paste.
    let snapshot = PasteboardSnapshot.capture(from: .general)

    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(trimmed, forType: .string)

    try sendPasteShortcut()

    // Best-effort restore after a small delay to give the target app time to read the clipboard.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      _ = snapshot.restore(to: .general)
    }
  }

  private func sendPasteShortcut() throws {
    let keyV: CGKeyCode = 9 // kVK_ANSI_V

    guard let source = CGEventSource(stateID: .hidSystemState) else {
      throw InsertError.failedToCreateEvents
    }

    let flags: CGEventFlags = [.maskCommand]

    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
    else {
      throw InsertError.failedToCreateEvents
    }

    keyDown.flags = flags
    keyUp.flags = flags

    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
  }
}
