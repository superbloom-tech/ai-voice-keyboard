import Foundation

enum LLMAPIClientFactoryError: LocalizedError {
  case missingModel
  case missingAPIKey
  case invalidBaseURL(String)
  case keychainError(underlying: Error)

  var errorDescription: String? {
    switch self {
    case .missingModel:
      return "Missing model"
    case .missingAPIKey:
      return "API key not saved"
    case .invalidBaseURL(let baseURL):
      return "Invalid Base URL: \(baseURL)"
    case .keychainError(let error):
      return "Keychain error: \(error.localizedDescription)"
    }
  }
}

/// Creates provider-specific `LLMAPIClient` instances from the persisted config.
struct LLMAPIClientFactory {
  static func create(config: PostProcessingConfig) throws -> LLMAPIClient {
    let model = (config.refinerModel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !model.isEmpty else {
      throw LLMAPIClientFactoryError.missingModel
    }

    // Resolve base URL (allows empty input to fall back to defaults).
    let baseURLString = config.resolvedRefinerBaseURLString
    guard let baseURL = URL(string: baseURLString) else {
      throw LLMAPIClientFactoryError.invalidBaseURL(baseURLString)
    }

    let apiKey: String
    do {
      guard let key = try config.loadLLMAPIKey(),
            !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw LLMAPIClientFactoryError.missingAPIKey
      }
      apiKey = key
    } catch let error as LLMAPIClientFactoryError {
      throw error
    } catch {
      throw LLMAPIClientFactoryError.keychainError(underlying: error)
    }

    switch config.refinerProviderFormat {
    case .openAICompatible:
      return OpenAIClient(apiKey: apiKey, model: model, baseURL: baseURL)
    case .anthropic:
      return AnthropicClient(apiKey: apiKey, model: model, baseURL: baseURL)
    }
  }
}

