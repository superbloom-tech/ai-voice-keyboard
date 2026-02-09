import XCTest
@testable import AIVoiceKeyboard

final class LLMEndpointTests: XCTestCase {
  func testOpenAICompatibleAppendsChatCompletions() throws {
    let base = try XCTUnwrap(URL(string: "https://api.openai.com/v1"))
    let url = LLMEndpoint.makeEndpointURL(baseURL: base, endpointPath: "/chat/completions")
    XCTAssertEqual(url.absoluteString, "https://api.openai.com/v1/chat/completions")
  }

  func testOpenAICompatibleHandlesTrailingSlash() throws {
    let base = try XCTUnwrap(URL(string: "https://openrouter.ai/api/v1/"))
    let url = LLMEndpoint.makeEndpointURL(baseURL: base, endpointPath: "chat/completions")
    XCTAssertEqual(url.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
  }

  func testDoesNotDuplicateEndpointIfAlreadyPresent() throws {
    let base = try XCTUnwrap(URL(string: "https://api.openai.com/v1/chat/completions"))
    let url = LLMEndpoint.makeEndpointURL(baseURL: base, endpointPath: "/chat/completions")
    XCTAssertEqual(url.absoluteString, "https://api.openai.com/v1/chat/completions")
  }

  func testAnthropicAppendsMessages() throws {
    let base = try XCTUnwrap(URL(string: "https://api.anthropic.com/v1"))
    let url = LLMEndpoint.makeEndpointURL(baseURL: base, endpointPath: "/messages")
    XCTAssertEqual(url.absoluteString, "https://api.anthropic.com/v1/messages")
  }
}

