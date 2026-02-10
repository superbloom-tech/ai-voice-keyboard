import Foundation

/// A saved LLM Refiner configuration (Issue #42).
struct RefinerProfile: Codable, Identifiable, Hashable {
  var id: UUID
  var name: String
  var enabled: Bool

  var providerFormat: LLMProviderFormat
  var openAICompatiblePreset: OpenAICompatiblePreset

  /// Base URL without endpoint path, e.g. `https://api.openai.com/v1`.
  var baseURL: String
  var model: String?
  var timeout: TimeInterval

  /// Store `PostProcessingPipeline.FallbackBehavior` as an Int for Codable stability.
  var fallbackBehaviorRawValue: Int

  init(
    id: UUID = UUID(),
    name: String,
    enabled: Bool,
    providerFormat: LLMProviderFormat,
    openAICompatiblePreset: OpenAICompatiblePreset,
    baseURL: String,
    model: String?,
    timeout: TimeInterval,
    fallbackBehavior: PostProcessingPipeline.FallbackBehavior
  ) {
    self.id = id
    self.name = name
    self.enabled = enabled
    self.providerFormat = providerFormat
    self.openAICompatiblePreset = openAICompatiblePreset
    self.baseURL = baseURL
    self.model = model
    self.timeout = timeout
    self.fallbackBehaviorRawValue = {
      switch fallbackBehavior {
      case .returnOriginal: return 0
      case .returnLastValid: return 1
      case .throwError: return 2
      }
    }()
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

  /// Key used to store this profile's API key in Keychain.
  var apiKeyKeychainKey: String {
    "llm.profile.\(id.uuidString.lowercased())"
  }

  /// Canonical base URL used when constructing the provider endpoint.
  /// If `baseURL` is blank, falls back to a reasonable default per provider/preset.
  var resolvedBaseURLString: String {
    let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      switch providerFormat {
      case .openAICompatible:
        switch openAICompatiblePreset {
        case .openai:
          return PostProcessingConfig.defaultOpenAIBaseURLString
        case .openrouter:
          return PostProcessingConfig.defaultOpenRouterBaseURLString
        case .custom:
          return PostProcessingConfig.defaultOpenAIBaseURLString
        }
      case .anthropic:
        return PostProcessingConfig.defaultAnthropicBaseURLString
      }
    }
    return trimmed
  }
}

/// Configuration for post-processing pipeline
struct PostProcessingConfig: Codable {
  var enabled: Bool
  var cleanerEnabled: Bool
  var cleanerRulesRawValue: Int  // Store CleaningRules.rawValue for Codable
  var cleanerTimeout: TimeInterval  // Timeout for TextCleaner (local processing)

  // Issue #42: multiple saved refiner profiles + manual switching.
  var refinerProfiles: [RefinerProfile]
  var selectedRefinerProfileId: UUID

  // Not persisted: set when decoding legacy single-refiner configs so we can migrate Keychain entries in `load()`.
  private var needsLegacyKeyMigration: Bool = false
  
  var cleanerRules: TextCleaner.CleaningRules {
    get { TextCleaner.CleaningRules(rawValue: cleanerRulesRawValue) }
    set { cleanerRulesRawValue = newValue.rawValue }
  }

  var selectedRefinerProfile: RefinerProfile? {
    refinerProfiles.first(where: { $0.id == selectedRefinerProfileId })
  }

  private mutating func normalizeProfilesIfNeeded() {
    if refinerProfiles.isEmpty {
      let profile = RefinerProfile(
        name: "Default",
        enabled: false,
        providerFormat: .openAICompatible,
        openAICompatiblePreset: .openai,
        baseURL: Self.defaultOpenAIBaseURLString,
        model: nil,
        timeout: 2.0,
        fallbackBehavior: .returnOriginal
      )
      refinerProfiles = [profile]
      selectedRefinerProfileId = profile.id
      return
    }

    if !refinerProfiles.contains(where: { $0.id == selectedRefinerProfileId }) {
      selectedRefinerProfileId = refinerProfiles[0].id
    }
  }

  private mutating func updateSelectedProfile(_ update: (inout RefinerProfile) -> Void) {
    normalizeProfilesIfNeeded()
    guard let idx = refinerProfiles.firstIndex(where: { $0.id == selectedRefinerProfileId }) else { return }
    update(&refinerProfiles[idx])
  }

  // MARK: - Selected profile convenience accessors (backward-compatible call sites)

  var refinerEnabled: Bool {
    get { selectedRefinerProfile?.enabled ?? false }
    set { updateSelectedProfile { $0.enabled = newValue } }
  }

  var refinerTimeout: TimeInterval {
    get { selectedRefinerProfile?.timeout ?? 2.0 }
    set { updateSelectedProfile { $0.timeout = newValue } }
  }

  var refinerModel: String? {
    get { selectedRefinerProfile?.model }
    set { updateSelectedProfile { $0.model = newValue } }
  }

  var refinerProviderFormat: LLMProviderFormat {
    get { selectedRefinerProfile?.providerFormat ?? .openAICompatible }
    set { updateSelectedProfile { $0.providerFormat = newValue } }
  }

  var refinerOpenAICompatiblePreset: OpenAICompatiblePreset {
    get { selectedRefinerProfile?.openAICompatiblePreset ?? .openai }
    set { updateSelectedProfile { $0.openAICompatiblePreset = newValue } }
  }

  var refinerBaseURL: String {
    get { selectedRefinerProfile?.baseURL ?? Self.defaultOpenAIBaseURLString }
    set { updateSelectedProfile { $0.baseURL = newValue } }
  }

  var resolvedRefinerBaseURLString: String {
    selectedRefinerProfile?.resolvedBaseURLString ?? Self.defaultOpenAIBaseURLString
  }

  var fallbackBehaviorRawValue: Int {
    get { selectedRefinerProfile?.fallbackBehaviorRawValue ?? 0 }
    set { updateSelectedProfile { $0.fallbackBehaviorRawValue = newValue } }
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
    refinerProfiles: [RefinerProfile],
    selectedRefinerProfileId: UUID
  ) {
    self.enabled = enabled
    self.cleanerEnabled = cleanerEnabled
    self.cleanerRulesRawValue = cleanerRules.rawValue
    self.cleanerTimeout = cleanerTimeout
    self.refinerProfiles = refinerProfiles
    self.selectedRefinerProfileId = selectedRefinerProfileId
    self.needsLegacyKeyMigration = false

    normalizeProfilesIfNeeded()
  }
  
  static let `default`: PostProcessingConfig = {
    let profile = RefinerProfile(
      name: "Default",
      enabled: false,
      providerFormat: .openAICompatible,
      openAICompatiblePreset: .openai,
      baseURL: PostProcessingConfig.defaultOpenAIBaseURLString,
      model: nil,
      timeout: 2.0,
      fallbackBehavior: .returnOriginal
    )
    return PostProcessingConfig(
      enabled: true,
      cleanerEnabled: true,
      cleanerRules: .standard,
      cleanerTimeout: 1.0,
      refinerProfiles: [profile],
      selectedRefinerProfileId: profile.id
    )
  }()
  
  static let v0Only: PostProcessingConfig = {
    let profile = RefinerProfile(
      name: "Default",
      enabled: false,
      providerFormat: .openAICompatible,
      openAICompatiblePreset: .openai,
      baseURL: PostProcessingConfig.defaultOpenAIBaseURLString,
      model: nil,
      timeout: 2.0,
      fallbackBehavior: .returnOriginal
    )
    return PostProcessingConfig(
      enabled: true,
      cleanerEnabled: true,
      cleanerRules: .standard,
      cleanerTimeout: 1.0,
      refinerProfiles: [profile],
      selectedRefinerProfileId: profile.id
    )
  }()
  
  static let disabled: PostProcessingConfig = {
    let profile = RefinerProfile(
      name: "Default",
      enabled: false,
      providerFormat: .openAICompatible,
      openAICompatiblePreset: .openai,
      baseURL: PostProcessingConfig.defaultOpenAIBaseURLString,
      model: nil,
      timeout: 2.0,
      fallbackBehavior: .returnOriginal
    )
    return PostProcessingConfig(
      enabled: false,
      cleanerEnabled: false,
      cleanerRules: .basic,
      cleanerTimeout: 1.0,
      refinerProfiles: [profile],
      selectedRefinerProfileId: profile.id
    )
  }()

  static let defaultOpenAIBaseURLString = "https://api.openai.com/v1"
  static let defaultOpenRouterBaseURLString = "https://openrouter.ai/api/v1"
  static let defaultAnthropicBaseURLString = "https://api.anthropic.com/v1"
  
  // MARK: - Codable (Backward Compatibility)
  
  enum CodingKeys: String, CodingKey {
    case enabled
    case cleanerEnabled
    case cleanerRulesRawValue
    case cleanerTimeout
    case refinerProfiles
    case selectedRefinerProfileId

    // Legacy single-refiner config keys (Issue #35 / Issue #33)
    case refinerEnabled
    case refinerTimeout
    case refinerModel
    case refinerProviderFormat
    case refinerOpenAICompatiblePreset
    case refinerBaseURL
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

    // New (Issue #42): profiles + selection
    if let decodedProfiles = try container.decodeIfPresent([RefinerProfile].self, forKey: .refinerProfiles),
       !decodedProfiles.isEmpty {
      refinerProfiles = decodedProfiles

      if let decodedSelected = try container.decodeIfPresent(UUID.self, forKey: .selectedRefinerProfileId),
         decodedProfiles.contains(where: { $0.id == decodedSelected }) {
        selectedRefinerProfileId = decodedSelected
      } else {
        selectedRefinerProfileId = decodedProfiles[0].id
      }

      needsLegacyKeyMigration = false
      normalizeProfilesIfNeeded()
      return
    }

    // Legacy single-refiner config migration (Issue #35 / Issue #33) => create a Default profile.
    let legacyRefinerEnabled = try container.decodeIfPresent(Bool.self, forKey: .refinerEnabled) ?? false
    let legacyTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .refinerTimeout) ?? 2.0
    let legacyModel = try container.decodeIfPresent(String.self, forKey: .refinerModel)
    let legacyFallbackRaw = try container.decodeIfPresent(Int.self, forKey: .fallbackBehaviorRawValue) ?? 0

    // Legacy provider string is used for backward compatibility.
    let legacyProviderString = try container.decodeIfPresent(String.self, forKey: .refinerProvider)
    let legacyProviderStringLower = legacyProviderString?.lowercased()
    let legacyProvider: LLMProvider? = {
      if let legacyProviderStringLower {
        return LLMProvider(rawValue: legacyProviderStringLower)
      }
      return try? container.decodeIfPresent(LLMProvider.self, forKey: .refinerProvider)
    }()

    // Provider format / preset / baseURL (prefer Issue #35 fields when present, otherwise derive from Issue #33).
    let format: LLMProviderFormat = (try container.decodeIfPresent(LLMProviderFormat.self, forKey: .refinerProviderFormat)) ?? {
      switch legacyProvider {
      case .anthropic:
        return .anthropic
      default:
        return .openAICompatible
      }
    }()

    let preset: OpenAICompatiblePreset = (try container.decodeIfPresent(OpenAICompatiblePreset.self, forKey: .refinerOpenAICompatiblePreset)) ?? {
      if legacyProviderStringLower == "openrouter" {
        return .openrouter
      }
      if legacyProviderStringLower == "custom" || legacyProviderStringLower == "ollama" {
        return .custom
      }
      return .openai
    }()

    let baseURL: String = (try container.decodeIfPresent(String.self, forKey: .refinerBaseURL)) ?? {
      switch format {
      case .openAICompatible:
        switch preset {
        case .openai: return Self.defaultOpenAIBaseURLString
        case .openrouter: return Self.defaultOpenRouterBaseURLString
        case .custom: return Self.defaultOpenAIBaseURLString
        }
      case .anthropic:
        return Self.defaultAnthropicBaseURLString
      }
    }()

    let profile = RefinerProfile(
      name: "Default",
      enabled: legacyRefinerEnabled,
      providerFormat: format,
      openAICompatiblePreset: preset,
      baseURL: baseURL,
      model: legacyModel,
      timeout: legacyTimeout,
      fallbackBehavior: {
        switch legacyFallbackRaw {
        case 1: return .returnLastValid
        case 2: return .throwError
        default: return .returnOriginal
        }
      }()
    )

    refinerProfiles = [profile]
    selectedRefinerProfileId = profile.id
    needsLegacyKeyMigration = true
    normalizeProfilesIfNeeded()
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(enabled, forKey: .enabled)
    try container.encode(cleanerEnabled, forKey: .cleanerEnabled)
    try container.encode(cleanerRulesRawValue, forKey: .cleanerRulesRawValue)
    try container.encode(cleanerTimeout, forKey: .cleanerTimeout)
    try container.encode(refinerProfiles, forKey: .refinerProfiles)
    try container.encode(selectedRefinerProfileId, forKey: .selectedRefinerProfileId)
  }
}

// MARK: - UserDefaults Persistence

extension PostProcessingConfig {
  private static let key = "avkb.postProcessing.config"
  
  static func load() -> PostProcessingConfig {
    guard let data = UserDefaults.standard.data(forKey: Self.key),
          var config = try? JSONDecoder().decode(PostProcessingConfig.self, from: data) else {
      return .default
    }

    // One-time migration: legacy single-refiner configs must migrate their API key
    // from the old preset namespace to the new per-profile Keychain key.
    if config.needsLegacyKeyMigration {
      config.migrateLegacyAPIKeyIfNeeded()
      config.needsLegacyKeyMigration = false
      config.save()
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

  private static func legacyNamespace(for profile: RefinerProfile) -> String {
    switch profile.providerFormat {
    case .openAICompatible:
      return profile.openAICompatiblePreset.rawValue
    case .anthropic:
      return "anthropic"
    }
  }

  private mutating func migrateLegacyAPIKeyIfNeeded() {
    guard let profile = selectedRefinerProfile else { return }
    let newKey = profile.apiKeyKeychainKey

    // Only migrate if the new per-profile key doesn't already exist.
    guard !KeychainManager.exists(key: newKey, service: Self.llmApiKeyService) else { return }

    let legacyKey = Self.legacyNamespace(for: profile)
    guard let legacyValue = try? KeychainManager.load(key: legacyKey, service: Self.llmApiKeyService),
          !legacyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }

    // Best-effort copy. Keep legacy entry to avoid breaking older builds.
    try? KeychainManager.save(key: newKey, value: legacyValue, service: Self.llmApiKeyService)
  }

  private static func profileKeychainKey(profileId: UUID) -> String {
    "llm.profile.\(profileId.uuidString.lowercased())"
  }

  func loadLLMAPIKey(profileId: UUID) throws -> String? {
    try KeychainManager.load(key: Self.profileKeychainKey(profileId: profileId), service: Self.llmApiKeyService)
  }

  func saveLLMAPIKey(_ apiKey: String, profileId: UUID) throws {
    try KeychainManager.save(
      key: Self.profileKeychainKey(profileId: profileId),
      value: apiKey,
      service: Self.llmApiKeyService
    )
    NotificationCenter.default.post(name: .avkbPostProcessingConfigDidChange, object: nil)
  }

  func deleteLLMAPIKey(profileId: UUID) throws {
    try KeychainManager.delete(key: Self.profileKeychainKey(profileId: profileId), service: Self.llmApiKeyService)
    NotificationCenter.default.post(name: .avkbPostProcessingConfigDidChange, object: nil)
  }

  func hasLLMAPIKey(profileId: UUID) -> Bool {
    KeychainManager.exists(key: Self.profileKeychainKey(profileId: profileId), service: Self.llmApiKeyService)
  }
  
  /// Load LLM API key from Keychain
  /// - Returns: The API key if available
  /// - Throws: KeychainError if the operation fails
  func loadLLMAPIKey() throws -> String? {
    try loadLLMAPIKey(profileId: selectedRefinerProfileId)
  }
  
  /// Save LLM API key to Keychain
  /// - Parameter apiKey: The API key to save
  /// - Throws: KeychainError if the operation fails
  func saveLLMAPIKey(_ apiKey: String) throws {
    try saveLLMAPIKey(apiKey, profileId: selectedRefinerProfileId)
  }
  
  /// Delete LLM API key from Keychain
  /// - Throws: KeychainError if the operation fails
  func deleteLLMAPIKey() throws {
    try deleteLLMAPIKey(profileId: selectedRefinerProfileId)
  }
  
  /// Check if LLM API key exists in Keychain
  /// - Returns: true if the key exists, false otherwise
  func hasLLMAPIKey() -> Bool {
    hasLLMAPIKey(profileId: selectedRefinerProfileId)
  }
}
