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
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let preview = String(trimmed.prefix(48))
    let axEnabled = isAccessibilityEnabled()
    NSLog("[Insert][Smart] insert requested — accessibility=%@, length=%d, preview=\"%@\"",
          axEnabled ? "YES" : "NO",
          trimmed.count,
          preview)

    if axEnabled {
      do {
        NSLog("[Insert][Smart] trying AX insert")
        let method = try ax.insert(text: text)
        NSLog("[Insert][Smart] AX insert finished — method=%@", method.rawValue)
        return method
      } catch {
        NSLog("[Insert][AX] failed (%@); falling back to paste.", error.localizedDescription)
        NSLog("[Insert][Smart] trying paste fallback")
        let method = try paste.insert(text: text)
        NSLog("[Insert][Smart] paste fallback finished — method=%@", method.rawValue)
        return method
      }
    }

    NSLog("[Insert][Smart] accessibility disabled; using paste")
    let method = try paste.insert(text: text)
    NSLog("[Insert][Smart] paste finished — method=%@", method.rawValue)
    return method
  }
}
