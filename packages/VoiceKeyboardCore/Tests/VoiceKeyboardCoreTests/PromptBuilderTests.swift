import XCTest
@testable import VoiceKeyboardCore

final class PromptBuilderTests: XCTestCase {
  func testRefineDictationPromptHasStrictRules() throws {
    let messages = PromptBuilder.refineDictationMessages(text: "um I think", languageHint: .en)
    XCTAssertGreaterThanOrEqual(messages.count, 2)

    XCTAssertEqual(messages.first?.role, .system)
    XCTAssertTrue(messages.first?.content.contains("Output only") == true)
    XCTAssertTrue(messages.first?.content.contains("Do not add") == true)
  }

  func testRefineDictationUsesChineseSystemPromptWhenLanguageHintIsZh() throws {
    let messages = PromptBuilder.refineDictationMessages(text: "嗯 我觉得", languageHint: .zh)
    XCTAssertGreaterThanOrEqual(messages.count, 2)

    XCTAssertEqual(messages.first?.role, .system)
    XCTAssertTrue(messages.first?.content.contains("你是一个语音口述清理引擎") == true)
    XCTAssertTrue(messages.first?.content.contains("不要翻译") == true)
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
    XCTAssertTrue(messages.first?.content.contains("你是一个编辑引擎") == true)
    XCTAssertTrue(messages.first?.content.contains("不要输出解释") == true)
  }
}

