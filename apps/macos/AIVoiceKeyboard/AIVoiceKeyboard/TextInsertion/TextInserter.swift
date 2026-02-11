import Foundation

enum TextInsertionMethod: String, Sendable {
  /// Inserted via Accessibility (AX) without mutating clipboard.
  case ax
  /// Inserted via clipboard + Cmd+V (best-effort). This only means we successfully posted the key chord,
  /// not that the target app actually accepted the paste.
  case paste
  /// Clipboard was populated, but we did not (or could not) post Cmd+V. User can paste manually.
  case pasteClipboardOnly
}

@MainActor
protocol TextInserter {
  @discardableResult
  func insert(text: String) throws -> TextInsertionMethod
}
