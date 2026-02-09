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
  var refinerProvider: LLMProvider?
  var fallbackBehaviorRawValue: Int  // Store FallbackBehavior as Int
  
  var cleanerRules: TextCleaner.CleaningRules {
    get { TextCleaner.CleaningRules(rawValue: cleanerRulesRawValue) }
    set { cleanerRulesRawValue = newValue.rawValue }
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
    refinerProvider: LLMProvider?,
    fallbackBehavior: PostProcessingPipeline.FallbackBehavior
  ) {
    self.enabled = enabled
    self.cleanerEnabled = cleanerEnabled
    self.cleanerRulesRawValue = cleanerRules.rawValue
    self.cleanerTimeout = cleanerTimeout
    self.refinerEnabled = refinerEnabled
    self.refinerTimeout = refinerTimeout
    self.refinerModel = refinerModel
    self.refinerProvider = refinerProvider
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
    refinerProvider: nil,
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
    refinerProvider: nil,
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
    refinerProvider: nil,
    fallbackBehavior: .returnOriginal
  )
  
  // MARK: - Codable (Backward Compatibility)
  
  enum CodingKeys: String, CodingKey {
    case enabled
    case cleanerEnabled
    case cleanerRulesRawValue
    case cleanerTimeout
    case refinerEnabled
    case refinerTimeout
    case refinerModel
    case refinerProvider
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
    
    // Backward compatibility: decode String and convert to LLMProvider
    if let providerString = try container.decodeIfPresent(String.self, forKey: .refinerProvider) {
      refinerProvider = try? LLMProvider(rawValue: providerString.lowercased())
    } else {
      refinerProvider = try container.decodeIfPresent(LLMProvider.self, forKey: .refinerProvider)
    }
    
    fallbackBehaviorRawValue = try container.decode(Int.self, forKey: .fallbackBehaviorRawValue)
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
  }
}

// MARK: - LLM API Key Management

extension PostProcessingConfig {
  /// Keychain service name for LLM API keys
  static let llmApiKeyService = "ai.voice.keyboard.llm.apikey"
  
  /// Load LLM API key from Keychain
  /// - Returns: The API key if available
  /// - Throws: KeychainError if the operation fails
  func loadLLMAPIKey() throws -> String? {
    guard let provider = refinerProvider else { return nil }
    return try KeychainManager.load(key: provider.rawValue, service: Self.llmApiKeyService)
  }
  
  /// Save LLM API key to Keychain
  /// - Parameter apiKey: The API key to save
  /// - Throws: KeychainError if the operation fails
  func saveLLMAPIKey(_ apiKey: String) throws {
    guard let provider = refinerProvider else { return }
    try KeychainManager.save(key: provider.rawValue, value: apiKey, service: Self.llmApiKeyService)
  }
  
  /// Delete LLM API key from Keychain
  /// - Throws: KeychainError if the operation fails
  func deleteLLMAPIKey() throws {
    guard let provider = refinerProvider else { return }
    try KeychainManager.delete(key: provider.rawValue, service: Self.llmApiKeyService)
  }
  
  /// Check if LLM API key exists in Keychain
  /// - Returns: true if the key exists, false otherwise
  func hasLLMAPIKey() -> Bool {
    guard let provider = refinerProvider else { return false }
    return KeychainManager.exists(key: provider.rawValue, service: Self.llmApiKeyService)
  }
}

