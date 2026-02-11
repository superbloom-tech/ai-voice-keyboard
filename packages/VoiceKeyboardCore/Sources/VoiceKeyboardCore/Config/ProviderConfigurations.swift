import Foundation

public struct OpenAICompatibleLLMConfiguration: Codable, Equatable, Sendable {
  public var baseURL: URL
  public var apiKeyId: String
  public var model: String
  public var requestTimeoutSeconds: Double

  public init(baseURL: URL, apiKeyId: String, model: String, requestTimeoutSeconds: Double) {
    self.baseURL = baseURL
    self.apiKeyId = apiKeyId
    self.model = model
    self.requestTimeoutSeconds = requestTimeoutSeconds
  }
}

public enum LLMProviderConfiguration: Codable, Equatable, Sendable {
  case openAICompatible(OpenAICompatibleLLMConfiguration)

  private enum CodingKeys: String, CodingKey {
    case type
    case config
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .openAICompatible(let cfg):
      try container.encode("openai_compatible", forKey: .type)
      try container.encode(cfg, forKey: .config)
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)
    switch type {
    case "openai_compatible":
      self = .openAICompatible(try container.decode(OpenAICompatibleLLMConfiguration.self, forKey: .config))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .type,
        in: container,
        debugDescription: "Unknown LLM provider type: \(type)"
      )
    }
  }
}

public struct AppleSpeechConfiguration: Codable, Equatable, Sendable {
  public var localeIdentifier: String?

  public init(localeIdentifier: String? = nil) {
    self.localeIdentifier = localeIdentifier
  }
}

public struct OpenAICompatibleSTTConfiguration: Codable, Equatable, Sendable {
  public var baseURL: URL
  public var apiKeyId: String
  public var model: String
  public var requestTimeoutSeconds: Double

  public init(baseURL: URL, apiKeyId: String, model: String, requestTimeoutSeconds: Double) {
    self.baseURL = baseURL
    self.apiKeyId = apiKeyId
    self.model = model
    self.requestTimeoutSeconds = requestTimeoutSeconds
  }
}

public struct SonioxRESTSTTConfiguration: Codable, Equatable, Sendable {
  public var baseURL: URL
  public var apiKeyId: String
  public var model: String
  public var requestTimeoutSeconds: Double

  public init(baseURL: URL, apiKeyId: String, model: String, requestTimeoutSeconds: Double) {
    self.baseURL = baseURL
    self.apiKeyId = apiKeyId
    self.model = model
    self.requestTimeoutSeconds = requestTimeoutSeconds
  }
}

public struct WhisperLocalConfiguration: Codable, Equatable, Sendable {
  /// Optional absolute path to the `whisper` executable.
  ///
  /// When nil, clients may attempt auto-detection (e.g. Homebrew default paths).
  public var executablePath: String?

  /// Whisper model name (e.g. "turbo", "base", "small").
  public var model: String

  /// Optional language code for transcription (e.g. "en", "zh").
  ///
  /// When nil, clients may enable auto language detection.
  public var language: String?

  /// Max wall-clock time allowed for running local inference.
  public var inferenceTimeoutSeconds: Double

  public init(
    executablePath: String? = nil,
    model: String = "turbo",
    language: String? = nil,
    inferenceTimeoutSeconds: Double = 60
  ) {
    self.executablePath = executablePath
    self.model = model
    self.language = language
    self.inferenceTimeoutSeconds = inferenceTimeoutSeconds
  }
}

public enum STTProviderConfiguration: Codable, Equatable, Sendable {
  case appleSpeech(AppleSpeechConfiguration)
  case whisperLocal(WhisperLocalConfiguration)
  case openAICompatible(OpenAICompatibleSTTConfiguration)
  case sonioxREST(SonioxRESTSTTConfiguration)

  private enum CodingKeys: String, CodingKey {
    case type
    case config
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .appleSpeech(let cfg):
      try container.encode("apple_speech", forKey: .type)
      try container.encode(cfg, forKey: .config)
    case .whisperLocal(let cfg):
      try container.encode("whisper_local", forKey: .type)
      try container.encode(cfg, forKey: .config)
    case .openAICompatible(let cfg):
      try container.encode("openai_compatible", forKey: .type)
      try container.encode(cfg, forKey: .config)
    case .sonioxREST(let cfg):
      try container.encode("soniox_rest", forKey: .type)
      try container.encode(cfg, forKey: .config)
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)
    switch type {
    case "apple_speech":
      self = .appleSpeech(try container.decode(AppleSpeechConfiguration.self, forKey: .config))
    case "whisper_local":
      self = .whisperLocal(try container.decode(WhisperLocalConfiguration.self, forKey: .config))
    case "openai_compatible":
      self = .openAICompatible(try container.decode(OpenAICompatibleSTTConfiguration.self, forKey: .config))
    case "soniox_rest":
      self = .sonioxREST(try container.decode(SonioxRESTSTTConfiguration.self, forKey: .config))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .type,
        in: container,
        debugDescription: "Unknown STT provider type: \(type)"
      )
    }
  }
}
