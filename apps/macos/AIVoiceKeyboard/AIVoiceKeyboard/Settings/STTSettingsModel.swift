import Combine
import Foundation
import VoiceKeyboardCore

enum STTProviderKind: String, CaseIterable, Identifiable {
  case appleSpeech = "apple_speech"
  case whisperLocal = "whisper_local"
  case openAICompatible = "openai_compatible"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .appleSpeech:
      return "Apple Speech"
    case .whisperLocal:
      return "Whisper (Local CLI)"
    case .openAICompatible:
      return "Remote (OpenAI-compatible)"
    }
  }
}

@MainActor
final class STTSettingsModel: ObservableObject {
  // Selected provider.
  @Published var selectedProvider: STTProviderKind = .appleSpeech

  // Apple Speech
  @Published var appleSpeechLocaleIdentifier: String = ""

  // Whisper (Local CLI)
  @Published var whisperExecutablePath: String = ""
  @Published var whisperModel: String = "turbo"
  @Published var whisperLanguage: String = ""
  @Published var whisperTimeoutSeconds: Double = 60

  // Remote (OpenAI-compatible)
  @Published var remoteBaseURLString: String = "https://api.openai.com/v1"
  @Published var remoteModel: String = "whisper-1"
  @Published var remoteApiKeyId: String = "openai"
  @Published var remoteTimeoutSeconds: Double = 30

  // UI-only Keychain editing state.
  @Published var apiKeyDraft: String = ""
  @Published var apiKeyMessage: String?
  @Published var apiKeyMessageIsError: Bool = false

  @Published var configMessage: String?
  @Published var configMessageIsError: Bool = false

  private var cancellables: Set<AnyCancellable> = []
  private var isBootstrapping: Bool = true

  init(configuration: STTProviderConfiguration = STTProviderStore.load()) {
    apply(configuration: configuration)

    // Avoid saving during init.
    isBootstrapping = false

    objectWillChange
      .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
      .sink { [weak self] _ in
        guard let self else { return }
        self.persistConfiguration()
      }
      .store(in: &cancellables)

    // Clear UI-only API key state when switching API key IDs.
    $remoteApiKeyId
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] _ in
        guard let self else { return }
        self.apiKeyDraft = ""
        self.apiKeyMessage = nil
        self.apiKeyMessageIsError = false
      }
      .store(in: &cancellables)
  }

  var hasRemoteAPIKey: Bool {
    let id = remoteApiKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return false }
    return STTKeychain.exists(apiKeyId: id)
  }

  func saveAPIKey() {
    let id = remoteApiKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else {
      apiKeyMessageIsError = true
      apiKeyMessage = "API key id cannot be empty."
      return
    }

    let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
      apiKeyMessageIsError = true
      apiKeyMessage = "API key cannot be empty."
      return
    }

    do {
      try STTKeychain.save(apiKey: key, apiKeyId: id)
      apiKeyDraft = ""
      apiKeyMessageIsError = false
      apiKeyMessage = "API key saved for id: \(id)."
    } catch {
      apiKeyMessageIsError = true
      apiKeyMessage = error.localizedDescription
    }
  }

  func deleteAPIKey() {
    let id = remoteApiKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return }

    do {
      try STTKeychain.delete(apiKeyId: id)
      apiKeyDraft = ""
      apiKeyMessageIsError = false
      apiKeyMessage = "API key deleted for id: \(id)."
    } catch {
      apiKeyMessageIsError = true
      apiKeyMessage = error.localizedDescription
    }
  }

  func applyDefaultRemoteBaseURL() {
    remoteBaseURLString = "https://api.openai.com/v1"
  }

  func applyDefaultRemoteModel() {
    remoteModel = "whisper-1"
  }

  func currentConfiguration() -> STTProviderConfiguration? {
    // Convert UI state to a Core configuration. Return nil when validation fails.
    switch selectedProvider {
    case .appleSpeech:
      let raw = appleSpeechLocaleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
      return .appleSpeech(AppleSpeechConfiguration(localeIdentifier: raw.isEmpty ? nil : raw))

    case .whisperLocal:
      let exec = whisperExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
      let model = whisperModel.trimmingCharacters(in: .whitespacesAndNewlines)
      let lang = whisperLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
      return .whisperLocal(WhisperLocalConfiguration(
        executablePath: exec.isEmpty ? nil : exec,
        model: model.isEmpty ? "turbo" : model,
        language: lang.isEmpty ? nil : lang,
        inferenceTimeoutSeconds: whisperTimeoutSeconds
      ))

    case .openAICompatible:
      let base = remoteBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let baseURL = URL(string: base), baseURL.scheme != nil else {
        return nil
      }

      let model = remoteModel.trimmingCharacters(in: .whitespacesAndNewlines)
      let keyId = remoteApiKeyId.trimmingCharacters(in: .whitespacesAndNewlines)

      return .openAICompatible(OpenAICompatibleSTTConfiguration(
        baseURL: baseURL,
        apiKeyId: keyId.isEmpty ? "openai" : keyId,
        model: model.isEmpty ? "whisper-1" : model,
        requestTimeoutSeconds: remoteTimeoutSeconds
      ))
    }
  }

  private func persistConfiguration() {
    guard !isBootstrapping else { return }

    guard let cfg = currentConfiguration() else {
      configMessageIsError = true
      configMessage = "Invalid STT configuration (e.g. Base URL must be a valid URL)."
      return
    }

    // Use Core validation for best-effort UX feedback.
    let issues = cfg.validate()
    if issues.contains(where: { $0.severity == .error }) {
      configMessageIsError = true
      configMessage = "STT configuration has errors. Please review the fields."
      return
    }

    STTProviderStore.save(cfg)
    configMessageIsError = false
    configMessage = nil
  }

  private func apply(configuration: STTProviderConfiguration) {
    switch configuration {
    case .appleSpeech(let cfg):
      selectedProvider = .appleSpeech
      appleSpeechLocaleIdentifier = cfg.localeIdentifier ?? ""

    case .whisperLocal(let cfg):
      selectedProvider = .whisperLocal
      whisperExecutablePath = cfg.executablePath ?? ""
      whisperModel = cfg.model
      whisperLanguage = cfg.language ?? ""
      whisperTimeoutSeconds = cfg.inferenceTimeoutSeconds

    case .openAICompatible(let cfg):
      selectedProvider = .openAICompatible
      remoteBaseURLString = cfg.baseURL.absoluteString
      remoteApiKeyId = cfg.apiKeyId
      remoteModel = cfg.model
      remoteTimeoutSeconds = cfg.requestTimeoutSeconds
    }
  }
}

