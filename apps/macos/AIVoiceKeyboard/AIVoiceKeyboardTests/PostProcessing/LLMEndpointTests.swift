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

final class ElevenLabsAPITests: XCTestCase {
  func testBaseURLV1_AppendsV1WhenMissing() throws {
    let base = try XCTUnwrap(URL(string: "https://api.elevenlabs.io"))
    let url = ElevenLabsAPI.baseURLV1(base)
    XCTAssertEqual(url.absoluteString, "https://api.elevenlabs.io/v1")
  }

  func testBaseURLV1_KeepsV1() throws {
    let base = try XCTUnwrap(URL(string: "https://api.elevenlabs.io/v1"))
    let url = ElevenLabsAPI.baseURLV1(base)
    XCTAssertEqual(url.absoluteString, "https://api.elevenlabs.io/v1")
  }

  func testBaseURLV1_HandlesTrailingSlash() throws {
    let base = try XCTUnwrap(URL(string: "https://api.elevenlabs.io/v1/"))
    let url = ElevenLabsAPI.baseURLV1(base)
    XCTAssertEqual(url.absoluteString, "https://api.elevenlabs.io/v1")
  }

  func testBaseURLV1_TrimsFullEndpoint() throws {
    let base = try XCTUnwrap(URL(string: "https://api.elevenlabs.io/v1/speech-to-text"))
    let url = ElevenLabsAPI.baseURLV1(base)
    XCTAssertEqual(url.absoluteString, "https://api.elevenlabs.io/v1")
  }

  func testDecodeTranscriptText_ChunkResponse() throws {
    let json = """
    {"text":"hello","language_code":"en","language_probability":1.0,"words":[]}
    """
    let text = try ElevenLabsSpeechToTextResponse.decodeTranscriptText(from: Data(json.utf8))
    XCTAssertEqual(text, "hello")
  }

  func testDecodeTranscriptText_MultichannelResponse() throws {
    let json = """
    {"transcripts":[{"text":"a"},{"text":"b"}]}
    """
    let text = try ElevenLabsSpeechToTextResponse.decodeTranscriptText(from: Data(json.utf8))
    XCTAssertEqual(text, "a\nb")
  }
}
