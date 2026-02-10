import Foundation
import XCTest
@testable import VoiceKeyboardCore

final class ProviderConfigurationCodableTests: XCTestCase {
  func testLLMProviderConfigurationCodableRoundTrip() throws {
    let cfg = LLMProviderConfiguration.openAICompatible(
      OpenAICompatibleLLMConfiguration(
        baseURL: URL(string: "https://api.example.com")!,
        apiKeyId: "key_openai",
        model: "gpt-4o-mini",
        requestTimeoutSeconds: 30
      )
    )

    let data = try JSONEncoder().encode(cfg)
    let decoded = try JSONDecoder().decode(LLMProviderConfiguration.self, from: data)
    XCTAssertEqual(decoded, cfg)
  }

  func testSTTProviderConfigurationCodableRoundTrip() throws {
    let cfg = STTProviderConfiguration.openAICompatible(
      OpenAICompatibleSTTConfiguration(
        baseURL: URL(string: "https://stt.example.com")!,
        apiKeyId: "key_stt",
        model: "whisper-1",
        requestTimeoutSeconds: 30
      )
    )

    let data = try JSONEncoder().encode(cfg)
    let decoded = try JSONDecoder().decode(STTProviderConfiguration.self, from: data)
    XCTAssertEqual(decoded, cfg)
  }

  func testWhisperLocalSTTProviderConfigurationCodableRoundTrip() throws {
    let cfg = STTProviderConfiguration.whisperLocal(
      WhisperLocalConfiguration(
        executablePath: "/opt/homebrew/bin/whisper",
        model: "turbo",
        language: "en",
        inferenceTimeoutSeconds: 60
      )
    )

    let data = try JSONEncoder().encode(cfg)
    let decoded = try JSONDecoder().decode(STTProviderConfiguration.self, from: data)
    XCTAssertEqual(decoded, cfg)
  }
}
