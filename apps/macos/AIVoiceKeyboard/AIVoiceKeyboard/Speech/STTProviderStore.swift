import Foundation
import VoiceKeyboardCore

enum STTProviderStore {
  static let providerConfigurationJSONKey = "avkb.stt.providerConfigurationJSON"

  static func load() -> STTProviderConfiguration {
    guard let json = UserDefaults.standard.string(forKey: providerConfigurationJSONKey),
          let data = json.data(using: .utf8),
          let cfg = try? JSONDecoder().decode(STTProviderConfiguration.self, from: data) else {
      return defaultConfiguration()
    }
    return cfg
  }

  static func save(_ cfg: STTProviderConfiguration) {
    guard let data = try? JSONEncoder().encode(cfg),
          let json = String(data: data, encoding: .utf8) else {
      return
    }
    UserDefaults.standard.set(json, forKey: providerConfigurationJSONKey)
  }

  static func defaultConfiguration() -> STTProviderConfiguration {
    .appleSpeech(AppleSpeechConfiguration(localeIdentifier: nil))
  }
}

enum STTKeychain {
  static let service = "ai.voice.keyboard.stt.apikey"

  static func load(apiKeyId: String) throws -> String? {
    try KeychainManager.load(key: apiKeyId, service: service)
  }

  static func save(apiKey: String, apiKeyId: String) throws {
    try KeychainManager.save(key: apiKeyId, value: apiKey, service: service)
  }

  static func delete(apiKeyId: String) throws {
    try KeychainManager.delete(key: apiKeyId, service: service)
  }

  static func exists(apiKeyId: String) -> Bool {
    KeychainManager.exists(key: apiKeyId, service: service)
  }
}

