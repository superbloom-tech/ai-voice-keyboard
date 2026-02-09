//
//  LLMProvider.swift
//  AIVoiceKeyboard
//
//  Enum for LLM provider types
//

import Foundation

/// Supported LLM providers
enum LLMProvider: String, Codable, CaseIterable {
  case openai = "openai"
  case anthropic = "anthropic"
  case ollama = "ollama"
  
  /// Custom decoder for case-insensitive matching
  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    
    // Case-insensitive matching
    guard let provider = LLMProvider.allCases.first(where: { $0.rawValue.lowercased() == rawValue.lowercased() }) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid LLM provider: \(rawValue). Supported providers: \(LLMProvider.allCases.map { $0.rawValue }.joined(separator: ", "))"
      )
    }
    
    self = provider
  }
}
