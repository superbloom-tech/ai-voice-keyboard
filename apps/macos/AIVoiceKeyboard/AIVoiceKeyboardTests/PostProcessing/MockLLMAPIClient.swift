//
//  MockLLMAPIClient.swift
//  AIVoiceKeyboardTests
//
//  Mock implementation of LLMAPIClient for testing
//

import Foundation
@testable import AIVoiceKeyboard

/// Mock LLM API client for testing
final class MockLLMAPIClient: LLMAPIClient {
  let result: Result<String, LLMAPIError>
  
  init(result: Result<String, LLMAPIError>) {
    self.result = result
  }
  
  func refine(text: String, systemPrompt: String, timeout: TimeInterval) async throws -> String {
    switch result {
    case .success(let refined):
      return refined
    case .failure(let error):
      throw error
    }
  }
}
