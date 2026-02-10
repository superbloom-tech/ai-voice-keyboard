import Foundation

/// Higher-level API "format" for the LLM refiner.
///
/// - `openAICompatible`: Uses OpenAI-compatible `/chat/completions`
/// - `anthropic`: Uses Anthropic Messages `/messages`
enum LLMProviderFormat: String, Codable, CaseIterable {
  case openAICompatible = "openai-compatible"
  case anthropic = "anthropic"

  var displayName: String {
    switch self {
    case .openAICompatible:
      return NSLocalizedString("llm_provider_format.openai_compatible", comment: "")
    case .anthropic:
      return NSLocalizedString("llm_provider_format.anthropic", comment: "")
    }
  }

  /// Case-insensitive decoder for forward/backward compatibility.
  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    let lower = rawValue.lowercased()

    if let match = Self.allCases.first(where: { $0.rawValue.lowercased() == lower }) {
      self = match
      return
    }

    throw DecodingError.dataCorruptedError(
      in: container,
      debugDescription: "Invalid LLM provider format: \(rawValue). Supported: \(Self.allCases.map { $0.rawValue }.joined(separator: ", "))"
    )
  }
}

/// Presets for OpenAI-compatible providers. Used to namespace API keys in Keychain.
enum OpenAICompatiblePreset: String, Codable, CaseIterable {
  case openai = "openai"
  case openrouter = "openrouter"
  case custom = "custom"

  var displayName: String {
    switch self {
    case .openai:
      return NSLocalizedString("llm_openai_preset.openai", comment: "")
    case .openrouter:
      return NSLocalizedString("llm_openai_preset.openrouter", comment: "")
    case .custom:
      return NSLocalizedString("llm_openai_preset.custom", comment: "")
    }
  }

  /// Case-insensitive decoder for forward/backward compatibility.
  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    let lower = rawValue.lowercased()

    if let match = Self.allCases.first(where: { $0.rawValue.lowercased() == lower }) {
      self = match
      return
    }

    throw DecodingError.dataCorruptedError(
      in: container,
      debugDescription: "Invalid OpenAI-compatible preset: \(rawValue). Supported: \(Self.allCases.map { $0.rawValue }.joined(separator: ", "))"
    )
  }
}
