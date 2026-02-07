import Foundation

public struct DisfluencyCleaner: Sendable {
  public init() {}

  public func clean(_ text: String, languageHint: LanguageHint? = nil) -> String {
    var s = text

    // Normalize whitespace first to make token-based cleanup more reliable.
    s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    s = removeFillers(s, languageHint: languageHint)
    s = compressStutters(s, languageHint: languageHint)

    // Final whitespace normalization.
    s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    return s
  }

  private func removeFillers(_ text: String, languageHint: LanguageHint?) -> String {
    var s = text

    let useZh = languageHint == nil || languageHint == .auto || languageHint == .zh
    let useEn = languageHint == nil || languageHint == .auto || languageHint == .en

    if useEn {
      // Remove standalone English fillers.
      // Example: "um I think uh this" -> "I think this"
      s = s.replacingOccurrences(
        of: #"(?i)\b(um+|uh+|erm+|er+|ah+|hmm+)\b\s*"#,
        with: "",
        options: .regularExpression
      )
    }

    if useZh {
      // Remove common Chinese hesitation tokens, especially at boundaries.
      // - Leading filler: "嗯 我觉得..." -> "我觉得..."
      // - After punctuation: "我觉得，嗯，这个" -> "我觉得，这个"
      s = s.replacingOccurrences(
        of: #"^(嗯+|啊+|呃+|额+|诶+|唉+|em+)\s*"#,
        with: "",
        options: [.regularExpression, .caseInsensitive]
      )

      s = s.replacingOccurrences(
        of: #"([，。！？、,!.?\s]+)(嗯+|啊+|呃+|额+|诶+|唉+|em+)\s*"#,
        with: "$1",
        options: [.regularExpression, .caseInsensitive]
      )
    }

    return s
  }

  private func compressStutters(_ text: String, languageHint: LanguageHint?) -> String {
    var s = text

    let useZh = languageHint == nil || languageHint == .auto || languageHint == .zh
    let useEn = languageHint == nil || languageHint == .auto || languageHint == .en

    if useEn {
      // Compress immediate word repetitions like "I I I think" -> "I think"
      // This is intentionally conservative: only adjacent repetitions.
      s = s.replacingOccurrences(
        of: #"(?i)\b([a-z']+)(\s+\1\b)+"#,
        with: "$1",
        options: .regularExpression
      )
    }

    if useZh {
      // Compress common stutter-prone single-character repeats (e.g. "我我觉得" -> "我觉得"),
      // but avoid touching common meaningful reduplications like "看看".
      let zhStutterChars = "我你他她这那"
      s = s.replacingOccurrences(
        of: "([\(zhStutterChars)])\\1+",
        with: "$1",
        options: .regularExpression
      )

      // Also handle spaced stutters: "我 我 觉得" -> "我 觉得" (then normalized later).
      s = s.replacingOccurrences(
        of: "([\(zhStutterChars)])(\\s+\\1)+",
        with: "$1",
        options: .regularExpression
      )
    }

    return s
  }
}
