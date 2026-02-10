import Foundation
import XCTest
@testable import VoiceKeyboardCore

final class ConfigurationValidationTests: XCTestCase {
  func testValidateOpenAICompatibleLLMConfigurationTimeoutMustBePositive() throws {
    let cfg = OpenAICompatibleLLMConfiguration(
      baseURL: URL(string: "https://api.example.com")!,
      apiKeyId: "k",
      model: "m",
      requestTimeoutSeconds: 0
    )

    let issues = cfg.validate()
    XCTAssertTrue(issues.contains { $0.field == "requestTimeoutSeconds" && $0.severity == .error })
  }

  func testValidateOpenAICompatibleConfigurationRejectsEmptyApiKeyIdAndModel() throws {
    let cfg = OpenAICompatibleSTTConfiguration(
      baseURL: URL(string: "https://api.example.com")!,
      apiKeyId: "  ",
      model: "",
      requestTimeoutSeconds: 10
    )

    let issues = cfg.validate()
    XCTAssertTrue(issues.contains { $0.field == "apiKeyId" && $0.severity == .error })
    XCTAssertTrue(issues.contains { $0.field == "model" && $0.severity == .error })
  }

  func testValidateBaseURLHttpIsWarning() throws {
    let cfg = OpenAICompatibleLLMConfiguration(
      baseURL: URL(string: "http://example.com")!,
      apiKeyId: "k",
      model: "m",
      requestTimeoutSeconds: 10
    )

    let issues = cfg.validate()
    XCTAssertTrue(issues.contains { $0.field == "baseURL" && $0.severity == .warning })
  }

  func testValidateWhisperLocalConfigurationRejectsEmptyModel() throws {
    let cfg = WhisperLocalConfiguration(
      executablePath: nil,
      model: "  ",
      language: nil,
      inferenceTimeoutSeconds: 30
    )

    let issues = cfg.validate()
    XCTAssertTrue(issues.contains { $0.field == "model" && $0.severity == .error })
  }

  func testValidateWhisperLocalConfigurationTimeoutMustBePositive() throws {
    let cfg = WhisperLocalConfiguration(
      executablePath: nil,
      model: "turbo",
      language: nil,
      inferenceTimeoutSeconds: 0
    )

    let issues = cfg.validate()
    XCTAssertTrue(issues.contains { $0.field == "inferenceTimeoutSeconds" && $0.severity == .error })
  }

  func testValidateWhisperLocalConfigurationExecutablePathMustNotBeWhitespaceWhenProvided() throws {
    let cfg = WhisperLocalConfiguration(
      executablePath: "   ",
      model: "turbo",
      language: nil,
      inferenceTimeoutSeconds: 30
    )

    let issues = cfg.validate()
    XCTAssertTrue(issues.contains { $0.field == "executablePath" && $0.severity == .error })
  }
}
