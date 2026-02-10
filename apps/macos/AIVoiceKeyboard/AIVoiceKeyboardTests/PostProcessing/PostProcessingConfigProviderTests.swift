import XCTest
@testable import AIVoiceKeyboard

final class PostProcessingConfigProviderTests: XCTestCase {
  func testAPIKeyNamespaceIsSeparatedByPreset() {
    var config = PostProcessingConfig.default
    config.refinerProviderFormat = .openAICompatible

    config.refinerOpenAICompatiblePreset = .openai
    XCTAssertEqual(config.llmAPIKeyNamespace, "openai")

    config.refinerOpenAICompatiblePreset = .openrouter
    XCTAssertEqual(config.llmAPIKeyNamespace, "openrouter")

    config.refinerOpenAICompatiblePreset = .custom
    XCTAssertEqual(config.llmAPIKeyNamespace, "custom")
  }

  func testAPIKeyNamespaceAnthropic() {
    var config = PostProcessingConfig.default
    config.refinerProviderFormat = .anthropic
    XCTAssertEqual(config.llmAPIKeyNamespace, "anthropic")
  }

  func testResolvedBaseURLFallsBackToDefaultsWhenEmpty() {
    var config = PostProcessingConfig.default
    config.refinerBaseURL = "   "

    config.refinerProviderFormat = .openAICompatible
    config.refinerOpenAICompatiblePreset = .openai
    XCTAssertEqual(config.resolvedRefinerBaseURLString, PostProcessingConfig.defaultOpenAIBaseURLString)

    config.refinerOpenAICompatiblePreset = .openrouter
    XCTAssertEqual(config.resolvedRefinerBaseURLString, PostProcessingConfig.defaultOpenRouterBaseURLString)

    config.refinerProviderFormat = .anthropic
    XCTAssertEqual(config.resolvedRefinerBaseURLString, PostProcessingConfig.defaultAnthropicBaseURLString)
  }
}

