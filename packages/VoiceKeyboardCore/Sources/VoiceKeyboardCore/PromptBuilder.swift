public enum PromptBuilder {
  public static func refineDictationMessages(text: String, languageHint: LanguageHint?) -> [ChatMessage] {
    let system = """
You are a voice dictation cleanup engine.

Rules:
- Remove hesitations/filler words and obvious stutters.
- Remove immediate word repetitions caused by thinking pauses.
- Keep meaning and wording as close as possible; do not paraphrase.
- Do not add any new information.
- Keep the original language(s); do not translate.
- Output only the cleaned text. Output only the final text, no quotes, no markdown, no explanations.
"""

    let user = """
Clean up the following dictated text:
<<<
\(text)
>>>
"""

    if let languageHint {
      return [
        ChatMessage(role: .system, content: system + "\n\nLanguage hint: \(languageHint.rawValue)"),
        ChatMessage(role: .user, content: user)
      ]
    }

    return [
      ChatMessage(role: .system, content: system),
      ChatMessage(role: .user, content: user)
    ]
  }

  public static func editSelectionMessages(
    selection: String,
    instruction: String,
    languageHint: LanguageHint?
  ) -> [ChatMessage] {
    let system = """
You are an editing engine that rewrites ONLY the provided selection according to the user's instruction.

Rules:
- Follow the instruction and rewrite only the selection.
- Do not add unrelated content.
- Do not output explanations.
- Output only the revised selection text.
"""

    let user = """
Instruction:
<<<
\(instruction)
>>>

Selection:
<<<
\(selection)
>>>
"""

    if let languageHint {
      return [
        ChatMessage(role: .system, content: system + "\n\nLanguage hint: \(languageHint.rawValue)"),
        ChatMessage(role: .user, content: user)
      ]
    }

    return [
      ChatMessage(role: .system, content: system),
      ChatMessage(role: .user, content: user)
    ]
  }
}

