import Foundation

/// Chooses the best available insertion method:
/// - Prefer AX native insertion when Accessibility is enabled.
/// - Fall back to clipboard + paste shortcut on failure.
@MainActor
final class SmartTextInserter: TextInserter {
  private let ax: any TextInserter
  private let paste: any TextInserter
  private let isAccessibilityEnabled: () -> Bool

  init(
    ax: (any TextInserter)? = nil,
    paste: (any TextInserter)? = nil,
    isAccessibilityEnabled: @escaping () -> Bool = { PermissionChecks.status(for: .accessibility).isSatisfied }
  ) {
    // Avoid default-argument evaluation outside the main actor.
    self.ax = ax ?? AXTextInserter()
    self.paste = paste ?? PasteTextInserter()
    self.isAccessibilityEnabled = isAccessibilityEnabled
  }

  @discardableResult
  func insert(text: String) throws -> TextInsertionMethod {
    if isAccessibilityEnabled() {
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
