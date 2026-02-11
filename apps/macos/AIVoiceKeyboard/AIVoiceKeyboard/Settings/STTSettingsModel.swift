import Combine
import Foundation
import VoiceKeyboardCore

enum STTProviderKind: String, CaseIterable, Identifiable {
  case appleSpeech = "apple_speech"
  case whisperLocal = "whisper_local"
  case openAICompatible = "openai_compatible"
  case sonioxREST = "soniox_rest"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .appleSpeech:
      return NSLocalizedString("stt_provider.apple_speech", comment: "")
    case .whisperLocal:
      return NSLocalizedString("stt_provider.whisper_local", comment: "")
    case .openAICompatible:
      return NSLocalizedString("stt_provider.openai_compatible", comment: "")
    case .sonioxREST:
      return NSLocalizedString("stt_provider.soniox_rest", comment: "")
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

  // Soniox (REST)
  @Published var sonioxBaseURLString: String = "https://api.soniox.com"
  @Published var sonioxModel: String = "stt-async-preview"
  @Published var sonioxApiKeyId: String = "soniox"
  @Published var sonioxTimeoutSeconds: Double = 60

  // UI-only Keychain editing state.
  @Published var apiKeyDraft: String = ""
  @Published var apiKeyMessage: String?
  @Published var apiKeyMessageIsError: Bool = false

  @Published var configMessage: String?
  @Published var configMessageIsError: Bool = false

  private var cancellables: Set<AnyCancellable> = []
  private var isBootstrapping: Bool = true
  private var lastPersistedConfiguration: STTProviderConfiguration?

  init(configuration: STTProviderConfiguration = STTProviderStore.load()) {
    apply(configuration: configuration)
    lastPersistedConfiguration = configuration

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

    $sonioxApiKeyId
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] _ in
        guard let self else { return }
        self.apiKeyDraft = ""
        self.apiKeyMessage = nil
        self.apiKeyMessageIsError = false
      }
      .store(in: &cancellables)

    $selectedProvider
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

  var hasSonioxAPIKey: Bool {
    let id = sonioxApiKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return false }
    return STTKeychain.exists(apiKeyId: id)
  }

  func saveAPIKey() {
    let id = selectedProvider == .sonioxREST
      ? sonioxApiKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
      : remoteApiKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else {
      apiKeyMessageIsError = true
      apiKeyMessage = NSLocalizedString("settings.stt.remote.api_key.error_id_empty", comment: "")
      return
    }

    let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
      apiKeyMessageIsError = true
      apiKeyMessage = NSLocalizedString("common.error.api_key_empty", comment: "")
      return
    }

    do {
      try STTKeychain.save(apiKey: key, apiKeyId: id)
      apiKeyDraft = ""
      apiKeyMessageIsError = false
      apiKeyMessage = String(
        format: NSLocalizedString("settings.stt.remote.api_key.saved_format", comment: ""),
        id
      )
    } catch {
      apiKeyMessageIsError = true
      apiKeyMessage = error.localizedDescription
    }
  }

  func deleteAPIKey() {
    let id = selectedProvider == .sonioxREST
      ? sonioxApiKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
      : remoteApiKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return }

    do {
      try STTKeychain.delete(apiKeyId: id)
      apiKeyDraft = ""
      apiKeyMessageIsError = false
      apiKeyMessage = String(
        format: NSLocalizedString("settings.stt.remote.api_key.deleted_format", comment: ""),
        id
      )
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

  func applyDefaultSonioxBaseURL() {
    sonioxBaseURLString = "https://api.soniox.com"
  }

  func applyDefaultSonioxModel() {
    sonioxModel = "stt-async-preview"
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

    case .sonioxREST:
      let base = sonioxBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let baseURL = URL(string: base), baseURL.scheme != nil else {
        return nil
      }

      let model = sonioxModel.trimmingCharacters(in: .whitespacesAndNewlines)
      let keyId = sonioxApiKeyId.trimmingCharacters(in: .whitespacesAndNewlines)

      return .sonioxREST(SonioxRESTSTTConfiguration(
        baseURL: baseURL,
        apiKeyId: keyId.isEmpty ? "soniox" : keyId,
        model: model.isEmpty ? "stt-async-preview" : model,
        requestTimeoutSeconds: sonioxTimeoutSeconds
      ))
    }
  }

  private func persistConfiguration() {
    guard !isBootstrapping else { return }

    guard let cfg = currentConfiguration() else {
      configMessageIsError = true
      configMessage = NSLocalizedString("settings.stt.validation.invalid_config", comment: "")
      return
    }

    // Use Core validation for best-effort UX feedback.
    let issues = cfg.validate()
    if issues.contains(where: { $0.severity == .error }) {
      configMessageIsError = true
      configMessage = NSLocalizedString("settings.stt.validation.has_errors", comment: "")
      return
    }

    configMessageIsError = false
    configMessage = nil

    // Avoid re-saving when only UI-only state (e.g. apiKeyDraft) changes.
    if lastPersistedConfiguration == cfg {
      return
    }

    STTProviderStore.save(cfg)
    lastPersistedConfiguration = cfg
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

    case .sonioxREST(let cfg):
      selectedProvider = .sonioxREST
      sonioxBaseURLString = cfg.baseURL.absoluteString
      sonioxApiKeyId = cfg.apiKeyId
      sonioxModel = cfg.model
      sonioxTimeoutSeconds = cfg.requestTimeoutSeconds
    }
  }
}
