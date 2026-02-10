import Foundation

/// Configuration for post-processing pipeline
struct PostProcessingConfig: Codable {
  var enabled: Bool
  var cleanerEnabled: Bool
  var cleanerRulesRawValue: Int  // Store CleaningRules.rawValue for Codable
  var cleanerTimeout: TimeInterval  // Timeout for TextCleaner (local processing)
  var refinerEnabled: Bool
  var refinerTimeout: TimeInterval  // Timeout for LLMRefiner (network call)
  var refinerModel: String?
  var refinerProviderFormat: LLMProviderFormat
  var refinerOpenAICompatiblePreset: OpenAICompatiblePreset
  /// Base URL without endpoint path, e.g. `https://api.openai.com/v1`.
  var refinerBaseURL: String
  var fallbackBehaviorRawValue: Int  // Store FallbackBehavior as Int
  
  var cleanerRules: TextCleaner.CleaningRules {
    get { TextCleaner.CleaningRules(rawValue: cleanerRulesRawValue) }
    set { cleanerRulesRawValue = newValue.rawValue }
  }

  /// Canonical base URL used by the refiner when constructing the endpoint.
  /// If `refinerBaseURL` is blank, falls back to a reasonable default per provider.
  var resolvedRefinerBaseURLString: String {
    let trimmed = refinerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      switch refinerProviderFormat {
      case .openAICompatible:
        switch refinerOpenAICompatiblePreset {
        case .openai:
          return Self.defaultOpenAIBaseURLString
        case .openrouter:
          return Self.defaultOpenRouterBaseURLString
        case .custom:
          return Self.defaultOpenAIBaseURLString
        }
      case .anthropic:
        return Self.defaultAnthropicBaseURLString
      }
    }
    return trimmed
  }

  /// Namespaces API keys in Keychain so switching presets doesn't overwrite other keys.
  var llmAPIKeyNamespace: String {
    switch refinerProviderFormat {
    case .openAICompatible:
      return refinerOpenAICompatiblePreset.rawValue
    case .anthropic:
      return "anthropic"
    }
  }
  
  var fallbackBehavior: PostProcessingPipeline.FallbackBehavior {
    get {
      switch fallbackBehaviorRawValue {
      case 0: return .returnOriginal
      case 1: return .returnLastValid
      case 2: return .throwError
      default: return .returnOriginal
      }
    }
    set {
      switch newValue {
      case .returnOriginal: fallbackBehaviorRawValue = 0
      case .returnLastValid: fallbackBehaviorRawValue = 1
      case .throwError: fallbackBehaviorRawValue = 2
      }
    }
  }
  
  init(
    enabled: Bool,
    cleanerEnabled: Bool,
    cleanerRules: TextCleaner.CleaningRules,
    cleanerTimeout: TimeInterval,
    refinerEnabled: Bool,
    refinerTimeout: TimeInterval,
    refinerModel: String?,
    refinerProviderFormat: LLMProviderFormat,
    refinerOpenAICompatiblePreset: OpenAICompatiblePreset,
    refinerBaseURL: String,
    fallbackBehavior: PostProcessingPipeline.FallbackBehavior
  ) {
    self.enabled = enabled
    self.cleanerEnabled = cleanerEnabled
    self.cleanerRulesRawValue = cleanerRules.rawValue
    self.cleanerTimeout = cleanerTimeout
    self.refinerEnabled = refinerEnabled
    self.refinerTimeout = refinerTimeout
    self.refinerModel = refinerModel
    self.refinerProviderFormat = refinerProviderFormat
    self.refinerOpenAICompatiblePreset = refinerOpenAICompatiblePreset
    self.refinerBaseURL = refinerBaseURL
    self.fallbackBehaviorRawValue = {
      switch fallbackBehavior {
      case .returnOriginal: return 0
      case .returnLastValid: return 1
      case .throwError: return 2
      }
    }()
  }
  
  static let `default` = PostProcessingConfig(
    enabled: true,
    cleanerEnabled: true,
    cleanerRules: .standard,
    cleanerTimeout: 1.0,
    refinerEnabled: false,
    refinerTimeout: 2.0,
    refinerModel: nil,
    refinerProviderFormat: .openAICompatible,
    refinerOpenAICompatiblePreset: .openai,
    refinerBaseURL: PostProcessingConfig.defaultOpenAIBaseURLString,
    fallbackBehavior: .returnOriginal
  )
  
  static let v0Only = PostProcessingConfig(
    enabled: true,
    cleanerEnabled: true,
    cleanerRules: .standard,
    cleanerTimeout: 1.0,
    refinerEnabled: false,
    refinerTimeout: 2.0,
    refinerModel: nil,
    refinerProviderFormat: .openAICompatible,
    refinerOpenAICompatiblePreset: .openai,
    refinerBaseURL: PostProcessingConfig.defaultOpenAIBaseURLString,
    fallbackBehavior: .returnOriginal
  )
  
  static let disabled = PostProcessingConfig(
    enabled: false,
    cleanerEnabled: false,
    cleanerRules: .basic,
    cleanerTimeout: 1.0,
    refinerEnabled: false,
    refinerTimeout: 2.0,
    refinerModel: nil,
    refinerProviderFormat: .openAICompatible,
    refinerOpenAICompatiblePreset: .openai,
    refinerBaseURL: PostProcessingConfig.defaultOpenAIBaseURLString,
    fallbackBehavior: .returnOriginal
  )

  static let defaultOpenAIBaseURLString = "https://api.openai.com/v1"
  static let defaultOpenRouterBaseURLString = "https://openrouter.ai/api/v1"
  static let defaultAnthropicBaseURLString = "https://api.anthropic.com/v1"
  
  // MARK: - Codable (Backward Compatibility)
  
  enum CodingKeys: String, CodingKey {
    case enabled
    case cleanerEnabled
    case cleanerRulesRawValue
    case cleanerTimeout
    case refinerEnabled
    case refinerTimeout
    case refinerModel
    case refinerProviderFormat
    case refinerOpenAICompatiblePreset
    case refinerBaseURL
    case refinerProvider  // legacy (Issue #33)
    case fallbackBehaviorRawValue
  }
  
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    enabled = try container.decode(Bool.self, forKey: .enabled)
    cleanerEnabled = try container.decode(Bool.self, forKey: .cleanerEnabled)
    cleanerRulesRawValue = try container.decode(Int.self, forKey: .cleanerRulesRawValue)
    // Default to 1.0 if cleanerTimeout is missing (backward compatibility)
    cleanerTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .cleanerTimeout) ?? 1.0
    refinerEnabled = try container.decode(Bool.self, forKey: .refinerEnabled)
    refinerTimeout = try container.decode(TimeInterval.self, forKey: .refinerTimeout)
    refinerModel = try container.decodeIfPresent(String.self, forKey: .refinerModel)

    // Legacy (Issue #33) provider string is used for backward compatibility.
    let legacyProviderString = try container.decodeIfPresent(String.self, forKey: .refinerProvider)
    let legacyProviderStringLower = legacyProviderString?.lowercased()
    let legacyProvider: LLMProvider? = {
      if let legacyProviderStringLower {
        return LLMProvider(rawValue: legacyProviderStringLower)
      }
      return try? container.decodeIfPresent(LLMProvider.self, forKey: .refinerProvider)
    }()

    // New fields (Issue #35)
    let decodedFormat = try container.decodeIfPresent(LLMProviderFormat.self, forKey: .refinerProviderFormat)
    let decodedPreset = try container.decodeIfPresent(OpenAICompatiblePreset.self, forKey: .refinerOpenAICompatiblePreset)
    let decodedBaseURL = try container.decodeIfPresent(String.self, forKey: .refinerBaseURL)

    if let decodedFormat {
      refinerProviderFormat = decodedFormat
    } else {
      // Legacy mapping from `refinerProvider` (Issue #33)
      switch legacyProvider {
      case .anthropic:
        refinerProviderFormat = .anthropic
      default:
        // `.openai`, `.ollama`, `nil`, etc.
        refinerProviderFormat = .openAICompatible
      }
    }

    if let decodedPreset {
      refinerOpenAICompatiblePreset = decodedPreset
    } else {
      // Derive preset from legacy provider when possible
      if legacyProviderStringLower == "openrouter" {
        refinerOpenAICompatiblePreset = .openrouter
      } else if legacyProviderStringLower == "custom" {
        refinerOpenAICompatiblePreset = .custom
      } else if legacyProviderStringLower == "ollama" {
        refinerOpenAICompatiblePreset = .custom
      } else {
        refinerOpenAICompatiblePreset = .openai
      }
    }

    // Base URL: if missing, use default for the selected provider.
    if let decodedBaseURL {
      refinerBaseURL = decodedBaseURL
    } else {
      switch refinerProviderFormat {
      case .openAICompatible:
        switch refinerOpenAICompatiblePreset {
        case .openai:
          refinerBaseURL = Self.defaultOpenAIBaseURLString
        case .openrouter:
          refinerBaseURL = Self.defaultOpenRouterBaseURLString
        case .custom:
          refinerBaseURL = Self.defaultOpenAIBaseURLString
        }
      case .anthropic:
        refinerBaseURL = Self.defaultAnthropicBaseURLString
      }
    }

    fallbackBehaviorRawValue = try container.decode(Int.self, forKey: .fallbackBehaviorRawValue)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(enabled, forKey: .enabled)
    try container.encode(cleanerEnabled, forKey: .cleanerEnabled)
    try container.encode(cleanerRulesRawValue, forKey: .cleanerRulesRawValue)
    try container.encode(cleanerTimeout, forKey: .cleanerTimeout)
    try container.encode(refinerEnabled, forKey: .refinerEnabled)
    try container.encode(refinerTimeout, forKey: .refinerTimeout)
    try container.encodeIfPresent(refinerModel, forKey: .refinerModel)
    try container.encode(refinerProviderFormat, forKey: .refinerProviderFormat)
    try container.encode(refinerOpenAICompatiblePreset, forKey: .refinerOpenAICompatiblePreset)
    try container.encode(refinerBaseURL, forKey: .refinerBaseURL)
    try container.encode(fallbackBehaviorRawValue, forKey: .fallbackBehaviorRawValue)
  }
}

// MARK: - UserDefaults Persistence

extension PostProcessingConfig {
  private static let key = "avkb.postProcessing.config"
  
  static func load() -> PostProcessingConfig {
    guard let data = UserDefaults.standard.data(forKey: Self.key),
          let config = try? JSONDecoder().decode(PostProcessingConfig.self, from: data) else {
      return .default
    }
    return config
  }
  
  func save() {
    guard let data = try? JSONEncoder().encode(self) else { return }
    UserDefaults.standard.set(data, forKey: Self.key)
    NotificationCenter.default.post(name: .avkbPostProcessingConfigDidChange, object: nil)
  }
}

extension Notification.Name {
  static let avkbPostProcessingConfigDidChange = Notification.Name("avkb.postProcessing.config.didChange")
}

// MARK: - LLM API Key Management

extension PostProcessingConfig {
  /// Keychain service name for LLM API keys
  static let llmApiKeyService = "ai.voice.keyboard.llm.apikey"
  
  /// Load LLM API key from Keychain
  /// - Returns: The API key if available
  /// - Throws: KeychainError if the operation fails
  func loadLLMAPIKey() throws -> String? {
    return try KeychainManager.load(key: llmAPIKeyNamespace, service: Self.llmApiKeyService)
  }
  
  /// Save LLM API key to Keychain
  /// - Parameter apiKey: The API key to save
  /// - Throws: KeychainError if the operation fails
  func saveLLMAPIKey(_ apiKey: String) throws {
    try KeychainManager.save(key: llmAPIKeyNamespace, value: apiKey, service: Self.llmApiKeyService)
    NotificationCenter.default.post(name: .avkbPostProcessingConfigDidChange, object: nil)
  }
  
  /// Delete LLM API key from Keychain
  /// - Throws: KeychainError if the operation fails
  func deleteLLMAPIKey() throws {
    try KeychainManager.delete(key: llmAPIKeyNamespace, service: Self.llmApiKeyService)
    NotificationCenter.default.post(name: .avkbPostProcessingConfigDidChange, object: nil)
  }
  
  /// Check if LLM API key exists in Keychain
  /// - Returns: true if the key exists, false otherwise
  func hasLLMAPIKey() -> Bool {
    return KeychainManager.exists(key: llmAPIKeyNamespace, service: Self.llmApiKeyService)
  }
}
