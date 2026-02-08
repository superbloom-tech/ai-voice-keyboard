import AppKit
import Foundation

/// v0.1 inserter: paste via clipboard + Cmd+V.
///
/// Tradeoffs:
/// - Fast to ship and works in many apps.
/// - Temporarily mutates clipboard; we restore best-effort.
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

  private let restoreDelaySeconds: Double

  init(restoreDelaySeconds: Double = 0.2) {
    self.restoreDelaySeconds = restoreDelaySeconds
  }

  func insert(text: String) throws {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw PasteInsertError.emptyText }

    let snapshot = PasteboardSnapshot.capture(from: .general)

    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(trimmed, forType: .string)

    try postPasteKeyChord()

    // Give the target app a moment to consume the clipboard before restoring.
    DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelaySeconds) {
      _ = snapshot.restore(to: .general)
    }
  }

  private func postPasteKeyChord() throws {
    // kVK_ANSI_V = 0x09 on Apple US keyboards.
    let virtualKeyV: CGKeyCode = 9

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
