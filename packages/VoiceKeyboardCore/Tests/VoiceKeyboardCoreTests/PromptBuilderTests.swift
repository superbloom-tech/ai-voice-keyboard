import XCTest
@testable import VoiceKeyboardCore

final class PromptBuilderTests: XCTestCase {
  func testRefineDictationPromptHasStrictRules() throws {
    let messages = PromptBuilder.refineDictationMessages(text: "um I think", languageHint: .en)
    XCTAssertGreaterThanOrEqual(messages.count, 2)

    XCTAssertEqual(messages.first?.role, .system)
    XCTAssertTrue(messages.first?.content.contains("Output only") == true)
    XCTAssertTrue(messages.first?.content.contains("Do not add") == true)
    XCTAssertTrue(messages.first?.content.contains("Language hint: en") == true)
  }

  func testRefineDictationUsesChineseSystemPromptWhenLanguageHintIsZh() throws {
    let messages = PromptBuilder.refineDictationMessages(text: "嗯 我觉得", languageHint: .zh)
    XCTAssertGreaterThanOrEqual(messages.count, 2)

    XCTAssertEqual(messages.first?.role, .system)
    XCTAssertTrue(messages.first?.content.contains("不要翻译") == true)
    XCTAssertTrue(messages.first?.content.contains("不要添加") == true)
    XCTAssertTrue(messages.first?.content.contains("Language hint: zh") == true)
  }

  func testRefineDictationUsesEnglishSystemPromptWhenLanguageHintIsAuto() throws {
    let messages = PromptBuilder.refineDictationMessages(text: "你好", languageHint: .auto)
    XCTAssertGreaterThanOrEqual(messages.count, 2)

    XCTAssertEqual(messages.first?.role, .system)
    XCTAssertTrue(messages.first?.content.contains("You are a voice dictation cleanup engine") == true)
    XCTAssertTrue(messages.first?.content.contains("Language hint: auto") == true)
  }

  func testEditSelectionPromptIncludesInstructionAndSelection() throws {
    let selection = "This is a draft."
    let instruction = "Make it more concise."
    let messages = PromptBuilder.editSelectionMessages(selection: selection, instruction: instruction, languageHint: .en)

    XCTAssertGreaterThanOrEqual(messages.count, 2)

    let user = messages.first { $0.role == .user }
    XCTAssertNotNil(user)
    XCTAssertTrue(user?.content.contains(instruction) == true)
    XCTAssertTrue(user?.content.contains(selection) == true)
  }

  func testEditSelectionUsesChineseSystemPromptWhenLanguageHintIsZh() throws {
    let selection = "这是一段草稿。"
    let instruction = "更精简一点。"
    let messages = PromptBuilder.editSelectionMessages(selection: selection, instruction: instruction, languageHint: .zh)

    XCTAssertGreaterThanOrEqual(messages.count, 2)

    XCTAssertEqual(messages.first?.role, .system)
    XCTAssertTrue(messages.first?.content.contains("不要翻译") == true)
    XCTAssertTrue(messages.first?.content.contains("不要添加") == true)
    XCTAssertTrue(messages.first?.content.contains("不要输出解释") == true)
    XCTAssertTrue(messages.first?.content.contains("Language hint: zh") == true)
  }

  func testEditSelectionUsesEnglishSystemPromptWhenLanguageHintIsAuto() throws {
    let messages = PromptBuilder.editSelectionMessages(selection: "你好", instruction: "简短一点", languageHint: .auto)
    XCTAssertGreaterThanOrEqual(messages.count, 2)

    XCTAssertEqual(messages.first?.role, .system)
    XCTAssertTrue(messages.first?.content.contains("You are an editing engine") == true)
    XCTAssertTrue(messages.first?.content.contains("Language hint: auto") == true)
  }
}

