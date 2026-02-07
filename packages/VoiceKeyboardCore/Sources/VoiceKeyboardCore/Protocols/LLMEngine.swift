public protocol LLMEngine: Sendable {
  var id: String { get }
  var displayName: String { get }

  /// Lightly clean up dictated text: remove hesitations/fillers/repetitions and add minimal punctuation.
  /// Must keep meaning and wording as close as possible.
  func refineDictation(_ text: String, languageHint: LanguageHint?) async throws -> String

  /// Apply an edit instruction to a selected text span. Must return only the revised selection text.
  func editSelection(selection: String, instruction: String, languageHint: LanguageHint?) async throws -> String
}

