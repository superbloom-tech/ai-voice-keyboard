import Foundation

enum TextInsertionMethod: String, Sendable {
  /// Inserted via Accessibility (AX) without mutating clipboard.
  case ax
  /// Inserted via clipboard + (best-effort) Cmd+V.
  case paste
}

protocol TextInserter {
  @discardableResult
  func insert(text: String) throws -> TextInsertionMethod
}
