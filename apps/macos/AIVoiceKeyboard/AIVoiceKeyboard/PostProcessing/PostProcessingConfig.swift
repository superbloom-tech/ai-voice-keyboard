import Foundation

/// Configuration for post-processing pipeline
struct PostProcessingConfig: Codable {
  var enabled: Bool
  var cleanerEnabled: Bool
  var cleanerRulesRawValue: Int  // Store CleaningRules.rawValue for Codable
  var refinerEnabled: Bool
  var refinerTimeout: TimeInterval
  var refinerModel: String?
  var refinerProvider: String?  // "openai" / "anthropic" / "ollama"
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
    refinerEnabled: Bool,
    refinerTimeout: TimeInterval,
    refinerModel: String?,
    refinerProvider: String?,
    fallbackBehavior: PostProcessingPipeline.FallbackBehavior
  ) {
    self.enabled = enabled
    self.cleanerEnabled = cleanerEnabled
    self.cleanerRulesRawValue = cleanerRules.rawValue
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
    refinerEnabled: false,
    refinerTimeout: 2.0,
    refinerModel: nil,
    refinerProvider: nil,
    fallbackBehavior: .returnOriginal
  )
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
    return try KeychainManager.load(key: provider, service: Self.llmApiKeyService)
  }
  
  /// Save LLM API key to Keychain
  /// - Parameter apiKey: The API key to save
  /// - Throws: KeychainError if the operation fails
  func saveLLMAPIKey(_ apiKey: String) throws {
    guard let provider = refinerProvider else { return }
    try KeychainManager.save(key: provider, value: apiKey, service: Self.llmApiKeyService)
  }
  
  /// Delete LLM API key from Keychain
  /// - Throws: KeychainError if the operation fails
  func deleteLLMAPIKey() throws {
    guard let provider = refinerProvider else { return }
    try KeychainManager.delete(key: provider, service: Self.llmApiKeyService)
  }
  
  /// Check if LLM API key exists in Keychain
  /// - Returns: true if the key exists, false otherwise
  func hasLLMAPIKey() -> Bool {
    guard let provider = refinerProvider else { return false }
    return KeychainManager.exists(key: provider, service: Self.llmApiKeyService)
  }
}

