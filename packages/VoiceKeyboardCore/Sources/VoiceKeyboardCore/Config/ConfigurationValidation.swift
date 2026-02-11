import Foundation

public enum ConfigurationValidationSeverity: String, Codable, Sendable {
  case warning
  case error
}

public struct ConfigurationValidationIssue: Codable, Equatable, Sendable {
  public var severity: ConfigurationValidationSeverity
  public var field: String
  public var message: String

  public init(severity: ConfigurationValidationSeverity, field: String, message: String) {
    self.severity = severity
    self.field = field
    self.message = message
  }
}

public enum ConfigurationValidation {
  public static let maxTimeoutSeconds: Double = 300

  static func validateTimeout(_ seconds: Double, field: String) -> [ConfigurationValidationIssue] {
    guard seconds.isFinite else {
      return [ConfigurationValidationIssue(severity: .error, field: field, message: "Timeout must be a finite number.")]
    }
    guard seconds > 0 else {
      return [ConfigurationValidationIssue(severity: .error, field: field, message: "Timeout must be > 0 seconds.")]
    }
    if seconds > maxTimeoutSeconds {
      return [ConfigurationValidationIssue(severity: .warning, field: field, message: "Timeout is unusually large (> \(Int(maxTimeoutSeconds))s).")]
    }
    return []
  }

  static func validateNonEmpty(_ value: String, field: String) -> [ConfigurationValidationIssue] {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? [ConfigurationValidationIssue(severity: .error, field: field, message: "Field must not be empty.")]
      : []
  }

  static func validateBaseURL(_ url: URL, field: String) -> [ConfigurationValidationIssue] {
    guard let scheme = url.scheme?.lowercased() else {
      return [ConfigurationValidationIssue(severity: .error, field: field, message: "Base URL must include a scheme (https://...).")]
    }

    if scheme == "https" {
      return []
    }

    // Allow HTTP only as a warning so self-hosted/local development isn't blocked by default.
    return [ConfigurationValidationIssue(
      severity: .warning,
      field: field,
      message: "Base URL is not HTTPS. Consider using HTTPS to avoid leaking API keys over the network."
    )]
  }
}

public extension OpenAICompatibleLLMConfiguration {
  func validate() -> [ConfigurationValidationIssue] {
    var issues: [ConfigurationValidationIssue] = []
    issues += ConfigurationValidation.validateBaseURL(baseURL, field: "baseURL")
    issues += ConfigurationValidation.validateNonEmpty(apiKeyId, field: "apiKeyId")
    issues += ConfigurationValidation.validateNonEmpty(model, field: "model")
    issues += ConfigurationValidation.validateTimeout(requestTimeoutSeconds, field: "requestTimeoutSeconds")
    return issues
  }
}

public extension OpenAICompatibleSTTConfiguration {
  func validate() -> [ConfigurationValidationIssue] {
    var issues: [ConfigurationValidationIssue] = []
    issues += ConfigurationValidation.validateBaseURL(baseURL, field: "baseURL")
    issues += ConfigurationValidation.validateNonEmpty(apiKeyId, field: "apiKeyId")
    issues += ConfigurationValidation.validateNonEmpty(model, field: "model")
    issues += ConfigurationValidation.validateTimeout(requestTimeoutSeconds, field: "requestTimeoutSeconds")
    return issues
  }
}

public extension SonioxRESTSTTConfiguration {
  func validate() -> [ConfigurationValidationIssue] {
    var issues: [ConfigurationValidationIssue] = []
    issues += ConfigurationValidation.validateBaseURL(baseURL, field: "baseURL")
    issues += ConfigurationValidation.validateNonEmpty(apiKeyId, field: "apiKeyId")
    issues += ConfigurationValidation.validateNonEmpty(model, field: "model")
    issues += ConfigurationValidation.validateTimeout(requestTimeoutSeconds, field: "requestTimeoutSeconds")
    return issues
  }
}

public extension WhisperLocalConfiguration {
  func validate() -> [ConfigurationValidationIssue] {
    var issues: [ConfigurationValidationIssue] = []

    issues += ConfigurationValidation.validateNonEmpty(model, field: "model")
    issues += ConfigurationValidation.validateTimeout(inferenceTimeoutSeconds, field: "inferenceTimeoutSeconds")

    if let executablePath {
      issues += ConfigurationValidation.validateNonEmpty(executablePath, field: "executablePath")
    }

    return issues
  }
}

public extension LLMProviderConfiguration {
  func validate() -> [ConfigurationValidationIssue] {
    switch self {
    case .openAICompatible(let cfg):
      return cfg.validate()
    }
  }
}

public extension STTProviderConfiguration {
  func validate() -> [ConfigurationValidationIssue] {
    switch self {
    case .appleSpeech:
      return []
    case .whisperLocal(let cfg):
      return cfg.validate()
    case .openAICompatible(let cfg):
      return cfg.validate()
    case .sonioxREST(let cfg):
      return cfg.validate()
    }
  }
}
