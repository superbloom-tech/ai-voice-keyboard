import ApplicationServices
import AppKit
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
    case selectedRangeOutOfBounds(original: CFRange, valueLength: Int)
    case verificationFailed(String)

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
      case .selectedRangeOutOfBounds(let r, let len):
        return "AX selected range out of bounds (location: \(r.location), length: \(r.length), valueLength: \(len))"
      case .verificationFailed(let reason):
        return "AX insert verification failed: \(reason)"
      }
    }
  }

  init() {}

  @discardableResult
  func insert(text: String) throws -> TextInsertionMethod {
    // Insert is designed for natural language dictation; we trim leading/trailing whitespace.
    // If we add "code mode" later, we should revisit this.
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw AXTextInsertError.emptyText }

    NSLog("[Insert][AX] attempting insert (length: %d)", trimmed.count)
    let insertedLen = (trimmed as NSString).length

    let systemWide = AXUIElementCreateSystemWide()
    let focused = try copyAXUIElementAttribute(systemWide, kAXFocusedUIElementAttribute as CFString)

    var pid: pid_t = 0
    AXUIElementGetPid(focused, &pid)
    let targetApp = NSRunningApplication(processIdentifier: pid)
    let targetAppName = targetApp?.localizedName ?? "unknown"
    let targetBundleId = targetApp?.bundleIdentifier ?? "unknown"

    let role = copyStringAttribute(focused, kAXRoleAttribute as CFString) ?? "unknown"
    let subrole = copyStringAttribute(focused, kAXSubroleAttribute as CFString) ?? "unknown"
    let selectedTextSettable = isAttributeSettable(focused, kAXSelectedTextAttribute as CFString)
    let valueSettable = isAttributeSettable(focused, kAXValueAttribute as CFString)

    NSLog(
      "[Insert][AX] focused pid=%d app=%@(%@) role=%@ subrole=%@ settableSelectedText=%@ settableValue=%@",
      pid,
      targetAppName,
      targetBundleId,
      role,
      subrole,
      selectedTextSettable ? "YES" : "NO",
      valueSettable ? "YES" : "NO"
    )

    // Prefer setting selected text directly when supported.
    if selectedTextSettable {
      let beforeCharCount = copyIntAttribute(focused, kAXNumberOfCharactersAttribute as CFString)
      let beforeSelectedRange = copySelectedTextRange(focused)
      let beforeValueForVerification: String? = {
        // Avoid reading large values unless we have to. We only use this to detect the "success but no-op"
        // cases when AXSelectedText claims to succeed.
        if let beforeCharCount {
          return beforeCharCount <= 4096 ? copyValueString(focused) : nil
        }
        return copyValueString(focused)
      }()

      if let beforeCharCount {
        NSLog("[Insert][AX] before AXSelectedText insert — charCount=%d", beforeCharCount)
      }
      if let beforeSelectedRange {
        NSLog(
          "[Insert][AX] before AXSelectedText insert — selectedRange=(loc=%ld len=%ld)",
          beforeSelectedRange.location,
          beforeSelectedRange.length
        )
      }
      if let beforeValueForVerification {
        NSLog("[Insert][AX] before AXSelectedText insert — valueLength=%d", (beforeValueForVerification as NSString).length)
      }

      let err = AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, trimmed as CFString)
      if err == .success {
        // Some apps (e.g. web text areas) can return `.success` but still ignore the write.
        // Only treat it as failure when we can confidently observe that nothing changed.
        if let beforeCharCount, let beforeSelectedRange {
          let expectedCharCount = beforeCharCount - beforeSelectedRange.length + insertedLen

          // Only verify via character count when we expect a length change (otherwise it can be a legit replacement).
          if expectedCharCount != beforeCharCount {
            let delaysUs: [useconds_t] = [0, 50_000, 100_000, 150_000] // total <= 300ms
            var afterCharCount: Int? = nil
            for delay in delaysUs {
              if delay > 0 { usleep(delay) }
              afterCharCount = copyIntAttribute(focused, kAXNumberOfCharactersAttribute as CFString)
              if let afterCharCount, afterCharCount != beforeCharCount { break }
            }

            if let afterCharCount {
              NSLog(
                "[Insert][AX] after AXSelectedText insert — charCount=%d (expected=%d, before=%d)",
                afterCharCount,
                expectedCharCount,
                beforeCharCount
              )

              if afterCharCount == beforeCharCount {
                if let beforeValueForVerification {
                  let delaysUs: [useconds_t] = [0, 50_000, 100_000, 150_000] // total <= 300ms
                  var afterValue: String? = nil
                  for delay in delaysUs {
                    if delay > 0 { usleep(delay) }
                    afterValue = copyValueString(focused)
                    if let afterValue, afterValue != beforeValueForVerification { break }
                  }

                  if let afterValue {
                    NSLog("[Insert][AX] after AXSelectedText insert — valueLength=%d", (afterValue as NSString).length)
                    if afterValue != beforeValueForVerification {
                      NSLog("[Insert][AX] inserted via AXSelectedText (verified by value change)")
                      return .ax
                    }
                  }

                  NSLog("[Insert][AX] AXSelectedText set returned success but no observable change; skipping AXValue to avoid double-insert")
                  throw AXTextInsertError.verificationFailed("AXSelectedText returned success but no observable change (pid=\(pid) app=\(targetBundleId))")
                } else {
                  NSLog("[Insert][AX] AXSelectedText set returned success but no observable change; skipping AXValue to avoid double-insert")
                  throw AXTextInsertError.verificationFailed("AXSelectedText returned success but no observable change (pid=\(pid) app=\(targetBundleId))")
                }
              } else {
                NSLog("[Insert][AX] inserted via AXSelectedText (verified by character count)")
                return .ax
              }
            } else {
              // Cannot verify; be conservative to avoid accidental double-insert.
              NSLog("[Insert][AX] inserted via AXSelectedText (verification skipped: cannot read char count)")
              return .ax
            }
          } else {
            NSLog("[Insert][AX] inserted via AXSelectedText (verification skipped: expectedCharCount == beforeCharCount)")
            return .ax
          }
        } else {
          // Cannot verify; be conservative to avoid accidental double-insert.
          NSLog("[Insert][AX] inserted via AXSelectedText (verification skipped)")
          return .ax
        }
      }
      if err != .success {
        NSLog("[Insert][AX] set selectedText failed (AXError: %d); falling back.", err.rawValue)
      }
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

    NSLog(
      "[Insert][AX] value replacement — selectedRange=(loc=%ld len=%ld) valueLength=%d",
      selectedRange.location,
      selectedRange.length,
      (currentValue as NSString).length
    )

    // Clamp to a safe UTF-16 range to avoid crashes from out-of-bounds ranges.
    let ns = currentValue as NSString
    let fullLen = ns.length
    let loc = max(0, min(selectedRange.location, fullLen))
    let len = max(0, min(selectedRange.length, fullLen - loc))
    let safeRange = NSRange(location: loc, length: len)

    // If AX returns an invalid/out-of-bounds range, prefer failing fast so `SmartTextInserter`
    // can fall back to the paste strategy instead of inserting into an unexpected position.
    if loc != selectedRange.location || len != selectedRange.length {
      NSLog(
        "[Insert][AX] Warning: selectedRange out of bounds (loc=%ld len=%ld fullLen=%ld); falling back to paste.",
        selectedRange.location,
        selectedRange.length,
        fullLen
      )
      throw AXTextInsertError.selectedRangeOutOfBounds(original: selectedRange, valueLength: fullLen)
    }

    let nextValue = ns.replacingCharacters(in: safeRange, with: trimmed)
    let setErr: AXError
    if currentValueObj is NSAttributedString {
      // Some apps expose AXValue as NSAttributedString; write back the same type for best compatibility.
      let nextAttr = NSAttributedString(string: nextValue)
      setErr = AXUIElementSetAttributeValue(focused, kAXValueAttribute as CFString, nextAttr as CFAttributedString)
    } else {
      setErr = AXUIElementSetAttributeValue(focused, kAXValueAttribute as CFString, nextValue as CFString)
    }
    guard setErr == .success else {
      throw AXTextInsertError.attributeWriteFailed("AXValue", setErr)
    }

    // Verify the write actually took effect. Some apps (especially Electron-based) process AX writes
    // asynchronously, so we retry with progressive delays before concluding the write was ignored.
    let verifyDelays: [useconds_t] = [0, 100_000, 200_000] // total <= 300ms
    var verifyValue: String = currentValue
    for delay in verifyDelays {
      if delay > 0 { usleep(delay) }
      let verifyObj = try copyAttributeValue(focused, kAXValueAttribute as CFString)
      if let s = verifyObj as? String {
        verifyValue = s
      } else if let s = (verifyObj as? NSAttributedString)?.string {
        verifyValue = s
      } else {
        throw AXTextInsertError.invalidAttributeType("AXValue")
      }
      if verifyValue != currentValue { break }
    }

    if verifyValue == currentValue {
      NSLog("[Insert][AX] verification failed: AXValue unchanged after set; falling back to paste")
      throw AXTextInsertError.verificationFailed("AXValue unchanged after set (pid=\(pid) app=\(targetBundleId))")
    }

    NSLog(
      "[Insert][AX] inserted via AXValue replacement (verified) (location: %ld, insertedLen: %d, beforeLen: %d, afterLen: %d)",
      loc,
      insertedLen,
      (currentValue as NSString).length,
      (verifyValue as NSString).length
    )

    // Best-effort: move the caret to the end of inserted text.
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

  private func copyIntAttribute(_ element: AXUIElement, _ attribute: CFString) -> Int? {
    var value: AnyObject?
    let err = AXUIElementCopyAttributeValue(element, attribute, &value)
    guard err == .success, let value else { return nil }
    return (value as? NSNumber)?.intValue
  }

  private func copySelectedTextRange(_ element: AXUIElement) -> CFRange? {
    var value: AnyObject?
    let err = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
    guard err == .success, let value else { return nil }
    guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

    var range = CFRange()
    guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
    return range
  }

  private func copyValueString(_ element: AXUIElement) -> String? {
    var value: AnyObject?
    let err = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
    guard err == .success, let value else { return nil }

    if let s = value as? String { return s }
    if let s = (value as? NSAttributedString)?.string { return s }
    return nil
  }
}
