public enum PromptBuilder {
  public static func refineDictationMessages(text: String, languageHint: LanguageHint?) -> [ChatMessage] {
    let system = systemPromptForRefineDictation(languageHint: languageHint)

    let user = """
Clean up the following dictated text:
<text>
\(text)
</text>
"""

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
    let system = systemPromptForEditSelection(languageHint: languageHint)

    let user = """
Instruction:
<instruction>
\(instruction)
</instruction>

Selection:
<selection>
\(selection)
</selection>
"""

    return [
      ChatMessage(role: .system, content: system),
      ChatMessage(role: .user, content: user)
    ]
  }

  private static func systemPromptForRefineDictation(languageHint: LanguageHint?) -> String {
    if languageHint == .zh {
      return """
你是一个语音口述清理引擎。

规则：
- 删除明显的口头禅/语气词/停顿词与卡顿（例如“嗯”“呃”“那个”“就是”）。
- 删除因思考停顿造成的紧邻重复词。
- 尽量保持原意与原措辞，不要改写/润色。
- 不要添加任何新信息。
- 保持原语言，不要翻译。
- 只输出清理后的文本；只输出最终文本；不要引号、不要 markdown、不要解释。
"""
    }

    return """
You are a voice dictation cleanup engine.

Rules:
- Remove hesitations/filler words and obvious stutters.
- Remove immediate word repetitions caused by thinking pauses.
- Keep meaning and wording as close as possible; do not paraphrase.
- Do not add any new information.
- Keep the original language(s); do not translate.
- Output only the cleaned text. Output only the final text, no quotes, no markdown, no explanations.
"""
  }

  private static func systemPromptForEditSelection(languageHint: LanguageHint?) -> String {
    if languageHint == .zh {
      return """
你是一个编辑引擎：只根据用户指令重写“给定选中内容”。

规则：
- 严格按照指令修改，并且只改写选中内容。
- 不要添加无关内容。
- 不要输出解释。
- 只输出改写后的选中内容文本。
"""
    }

    return """
You are an editing engine that rewrites ONLY the provided selection according to the user's instruction.

Rules:
- Follow the instruction and rewrite only the selection.
- Do not add unrelated content.
- Do not output explanations.
- Output only the revised selection text.
"""
  }
}
