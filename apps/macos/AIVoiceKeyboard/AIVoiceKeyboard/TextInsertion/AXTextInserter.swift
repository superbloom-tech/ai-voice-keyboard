import ApplicationServices
import Foundation

/// Attempts to insert/replace text using Accessibility (AX) without mutating clipboard.
final class AXTextInserter: TextInserter {
  enum AXTextInsertError: LocalizedError {
    case emptyText
    case noFocusedElement(AXError)
    case attributeReadFailed(String, AXError)
    case attributeWriteFailed(String, AXError)
    case attributeNotSettable(String)
    case invalidAttributeType(String)
    case invalidSelectedRange

    var errorDescription: String? {
      switch self {
      case .emptyText:
        return "Nothing to insert"
      case .noFocusedElement(let err):
        return "Cannot read focused UI element (AXError: \(err.rawValue))"
      case .attributeReadFailed(let attr, let err):
        return "Cannot read AX attribute \(attr) (AXError: \(err.rawValue))"
      case .attributeWriteFailed(let attr, let err):
        return "Cannot write AX attribute \(attr) (AXError: \(err.rawValue))"
      case .attributeNotSettable(let attr):
        return "AX attribute not settable: \(attr)"
      case .invalidAttributeType(let attr):
        return "Unexpected AX attribute type: \(attr)"
      case .invalidSelectedRange:
        return "Invalid AX selected text range"
      }
    }
  }

  init() {}

  @discardableResult
  func insert(text: String) throws -> TextInsertionMethod {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw AXTextInsertError.emptyText }

    let systemWide = AXUIElementCreateSystemWide()
    let focused = try copyAXUIElementAttribute(systemWide, kAXFocusedUIElementAttribute as CFString)

    let role = copyStringAttribute(focused, kAXRoleAttribute as CFString) ?? "unknown"
    let subrole = copyStringAttribute(focused, kAXSubroleAttribute as CFString) ?? "unknown"
    let selectedTextSettable = isAttributeSettable(focused, kAXSelectedTextAttribute as CFString)
    let valueSettable = isAttributeSettable(focused, kAXValueAttribute as CFString)

    NSLog(
      "[Insert][AX] focused role=%@ subrole=%@ settableSelectedText=%@ settableValue=%@",
      role,
      subrole,
      selectedTextSettable ? "YES" : "NO",
      valueSettable ? "YES" : "NO"
    )

    // Prefer setting selected text directly when supported.
    if selectedTextSettable {
      let err = AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, trimmed as CFString)
      if err == .success {
        return .ax
      }
      NSLog("[Insert][AX] set selectedText failed (AXError: %d); falling back.", err.rawValue)
    }

    // Fallback: replace the selected range in the element's value.
    guard valueSettable else {
      throw AXTextInsertError.attributeNotSettable("AXValue")
    }

    let selectedRangeValue = try copyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString)
    guard CFGetTypeID(selectedRangeValue) == AXValueGetTypeID() else {
      throw AXTextInsertError.invalidAttributeType("AXSelectedTextRange")
    }

    var selectedRange = CFRange()
    guard AXValueGetValue(selectedRangeValue as! AXValue, .cfRange, &selectedRange) else {
      throw AXTextInsertError.invalidSelectedRange
    }

    let currentValueObj = try copyAttributeValue(focused, kAXValueAttribute as CFString)
    let currentValue: String
    if let s = currentValueObj as? String {
      currentValue = s
    } else if let s = (currentValueObj as? NSAttributedString)?.string {
      currentValue = s
    } else {
      throw AXTextInsertError.invalidAttributeType("AXValue")
    }

    // Clamp to a safe UTF-16 range to avoid crashes from out-of-bounds ranges.
    let ns = currentValue as NSString
    let fullLen = ns.length
    let loc = max(0, min(selectedRange.location, fullLen))
    let len = max(0, min(selectedRange.length, fullLen - loc))
    let safeRange = NSRange(location: loc, length: len)

    let nextValue = ns.replacingCharacters(in: safeRange, with: trimmed)
    let setErr = AXUIElementSetAttributeValue(focused, kAXValueAttribute as CFString, nextValue as CFString)
    guard setErr == .success else {
      throw AXTextInsertError.attributeWriteFailed("AXValue", setErr)
    }

    // Best-effort: move the caret to the end of inserted text.
    let insertedLen = (trimmed as NSString).length
    var newRange = CFRange(location: loc + insertedLen, length: 0)
    if let axNewRange = AXValueCreate(.cfRange, &newRange) {
      _ = AXUIElementSetAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, axNewRange)
    }

    return .ax
  }

  private func isAttributeSettable(_ element: AXUIElement, _ attribute: CFString) -> Bool {
    var settable = DarwinBoolean(false)
    let err = AXUIElementIsAttributeSettable(element, attribute, &settable)
    return err == .success && settable.boolValue
  }

  private func copyAttributeValue(_ element: AXUIElement, _ attribute: CFString) throws -> AnyObject {
    var value: AnyObject?
    let err = AXUIElementCopyAttributeValue(element, attribute, &value)
    guard err == .success, let value else {
      throw AXTextInsertError.attributeReadFailed(attribute as String, err)
    }
    return value
  }

  private func copyAXUIElementAttribute(_ element: AXUIElement, _ attribute: CFString) throws -> AXUIElement {
    var value: AnyObject?
    let err = AXUIElementCopyAttributeValue(element, attribute, &value)
    guard err == .success, let value else {
      throw AXTextInsertError.noFocusedElement(err)
    }

    guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
      throw AXTextInsertError.invalidAttributeType(attribute as String)
    }

    return value as! AXUIElement
  }

  private func copyStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
    var value: AnyObject?
    let err = AXUIElementCopyAttributeValue(element, attribute, &value)
    guard err == .success else { return nil }
    return value as? String
  }
}
