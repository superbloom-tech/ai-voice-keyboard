import XCTest
@testable import AIVoiceKeyboard

final class PostProcessingConfigProviderTests: XCTestCase {
  func testAPIKeyKeychainKeyUsesLowercasedUUID() {
    let id = UUID(uuidString: "E5C06A08-3D23-4B3D-9D2E-6A8A2A0A3A4D")!
    let profile = RefinerProfile(
      id: id,
      name: "p",
      enabled: true,
      providerFormat: .openAICompatible,
      openAICompatiblePreset: .openai,
      baseURL: PostProcessingConfig.defaultOpenAIBaseURLString,
      model: "gpt-4o-mini",
      timeout: 2.0,
      fallbackBehavior: .returnOriginal
    )

    XCTAssertEqual(profile.apiKeyKeychainKey, "llm.profile.\(id.uuidString.lowercased())")
  }

  func testAPIKeyKeychainKeyDiffersBetweenProfiles() {
    let a = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let b = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    let p1 = RefinerProfile(
      id: a,
      name: "a",
      enabled: true,
      providerFormat: .openAICompatible,
      openAICompatiblePreset: .openai,
      baseURL: PostProcessingConfig.defaultOpenAIBaseURLString,
      model: nil,
      timeout: 2.0,
      fallbackBehavior: .returnOriginal
    )

    let p2 = RefinerProfile(
      id: b,
      name: "b",
      enabled: true,
      providerFormat: .openAICompatible,
      openAICompatiblePreset: .openai,
      baseURL: PostProcessingConfig.defaultOpenAIBaseURLString,
      model: nil,
      timeout: 2.0,
      fallbackBehavior: .returnOriginal
    )

    XCTAssertNotEqual(p1.apiKeyKeychainKey, p2.apiKeyKeychainKey)
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
