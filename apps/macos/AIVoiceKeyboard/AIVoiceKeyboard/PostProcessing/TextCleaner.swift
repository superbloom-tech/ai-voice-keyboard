import Foundation

/// Rule-based text cleaner for deterministic, low-latency post-processing
final class TextCleaner: PostProcessor {
  struct CleaningRules: OptionSet, Codable {
    let rawValue: Int
    
    static let trimWhitespace = CleaningRules(rawValue: 1 << 0)
    static let collapseWhitespace = CleaningRules(rawValue: 1 << 1)
    static let fixBasicPunctuation = CleaningRules(rawValue: 1 << 2)
    static let fixCapitalization = CleaningRules(rawValue: 1 << 3)
    static let removeFillerWords = CleaningRules(rawValue: 1 << 4)
    
    static let basic: CleaningRules = [.trimWhitespace, .collapseWhitespace]
    static let standard: CleaningRules = [.trimWhitespace, .collapseWhitespace, .fixBasicPunctuation]
    static let aggressive: CleaningRules = [.trimWhitespace, .collapseWhitespace, .fixBasicPunctuation, .fixCapitalization, .removeFillerWords]
  }
  
  private let rules: CleaningRules
  
  init(rules: CleaningRules = .standard) {
    self.rules = rules
  }
  
  func process(text: String, timeout: TimeInterval) async throws -> String {
    var result = text
    
    if rules.contains(.trimWhitespace) {
      result = result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    if rules.contains(.collapseWhitespace) {
      result = result.replacingOccurrences(
        of: "\\s+",
        with: " ",
        options: .regularExpression
      )
    }
    
    if rules.contains(.fixBasicPunctuation) {
      // Remove space before punctuation
      result = result.replacingOccurrences(
        of: "\\s+([.,!?;:])",
        with: "$1",
        options: .regularExpression
      )
      
      // Ensure space after punctuation (only when followed by a letter)
      // This avoids breaking numbers (3.14), URLs (example.com), times (10:30), etc.
      result = result.replacingOccurrences(
        of: "([.,!?;:])([a-zA-Z])",
        with: "$1 $2",
        options: .regularExpression
      )
    }
    
    if rules.contains(.fixCapitalization) {
      // Capitalize first letter
      if let first = result.first {
        result = first.uppercased() + result.dropFirst()
      }
      
      // Manual capitalization after punctuation
      var chars = Array(result)
      var shouldCapitalize = false
      for i in 0..<chars.count {
        if shouldCapitalize && chars[i].isLetter {
          chars[i] = Character(chars[i].uppercased())
          shouldCapitalize = false
        }
        if chars[i] == "." || chars[i] == "!" || chars[i] == "?" {
          shouldCapitalize = true
        }
      }
      result = String(chars)
    }
    
    if rules.contains(.removeFillerWords) {
      // Remove common filler words (um, uh, like, you know, etc.)
      let fillerPattern = "\\b(um|uh|like|you know|sort of|kind of)\\b"
      result = result.replacingOccurrences(
        of: fillerPattern,
        with: "",
        options: [.regularExpression, .caseInsensitive]
      )
      
      // Clean up any double spaces created by removal
      result = result.replacingOccurrences(
        of: "\\s+",
        with: " ",
        options: .regularExpression
      ).trimmingCharacters(in: .whitespaces)
    }
    
    return result
  }
}
