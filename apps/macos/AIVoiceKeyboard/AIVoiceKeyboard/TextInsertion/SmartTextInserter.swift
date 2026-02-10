import Foundation

/// Chooses the best available insertion method:
/// - Prefer AX native insertion when Accessibility is enabled.
/// - Fall back to clipboard + paste shortcut on failure.
final class SmartTextInserter: TextInserter {
  private let ax: AXTextInserter
  private let paste: PasteTextInserter

  init(ax: AXTextInserter = AXTextInserter(), paste: PasteTextInserter = PasteTextInserter()) {
    self.ax = ax
    self.paste = paste
  }

  @discardableResult
  func insert(text: String) throws -> TextInsertionMethod {
    if PermissionChecks.status(for: .accessibility).isSatisfied {
      do {
        return try ax.insert(text: text)
      } catch {
        NSLog("[Insert][AX] failed (%@); falling back to paste.", error.localizedDescription)
        return try paste.insert(text: text)
      }
    }

    return try paste.insert(text: text)
  }
}

