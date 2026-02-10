import Combine
import Foundation

@MainActor
final class PostProcessingSettingsModel: ObservableObject {
  @Published var config: PostProcessingConfig

  @Published var apiKeyDraft: String = ""
  @Published var apiKeyMessage: String?
  @Published var apiKeyMessageIsError: Bool = false

  @Published var isTesting: Bool = false
  @Published var testMessage: String?
  @Published var testMessageIsError: Bool = false

  private var cancellables: Set<AnyCancellable> = []

  init(config: PostProcessingConfig = .load()) {
    self.config = config

    // Clear UI-only API key state when switching profiles to avoid showing stale status/messages.
    $config
      .map(\.selectedRefinerProfileId)
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] _ in
        guard let self else { return }
        self.apiKeyDraft = ""
        self.apiKeyMessage = nil
        self.apiKeyMessageIsError = false
      }
      .store(in: &cancellables)

    // Avoid rebuilding the pipeline on every keystroke while editing Base URL / Model.
    $config
      .dropFirst()
      .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
      .sink { config in
        config.save()
      }
      .store(in: &cancellables)
  }

  var selectedProfile: RefinerProfile? {
    config.selectedRefinerProfile
  }

  func updateSelectedProfileName(_ name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let final = trimmed.isEmpty
      ? NSLocalizedString("settings.post_processing.profile.default_name", comment: "")
      : trimmed
    if let idx = config.refinerProfiles.firstIndex(where: { $0.id == config.selectedRefinerProfileId }) {
      config.refinerProfiles[idx].name = final
    }
  }

  func addProfile() {
    let name = makeUniqueProfileName(base: NSLocalizedString("settings.post_processing.profile.new_name", comment: ""))
    let profile = RefinerProfile(
      name: name,
      enabled: false,
      providerFormat: .openAICompatible,
      openAICompatiblePreset: .openai,
      baseURL: PostProcessingConfig.defaultOpenAIBaseURLString,
      model: nil,
      timeout: 2.0,
      fallbackBehavior: .returnOriginal
    )
    config.refinerProfiles.append(profile)
    config.selectedRefinerProfileId = profile.id
    apiKeyDraft = ""
    apiKeyMessage = nil
  }

  func duplicateSelectedProfile() {
    guard let selected = selectedProfile else { return }

    var copy = selected
    copy.id = UUID()
    let copySuffix = NSLocalizedString("settings.post_processing.profile.copy_suffix", comment: "")
    copy.name = makeUniqueProfileName(base: "\(selected.name) \(copySuffix)")
    config.refinerProfiles.append(copy)
    config.selectedRefinerProfileId = copy.id

    // Best-effort copy API key to the new profile.
    if let key = try? config.loadLLMAPIKey(profileId: selected.id),
       !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      try? config.saveLLMAPIKey(key, profileId: copy.id)
    }

    apiKeyDraft = ""
    apiKeyMessage = nil
  }

  func deleteSelectedProfile() {
    guard config.refinerProfiles.count > 1 else { return }
    let id = config.selectedRefinerProfileId

    config.refinerProfiles.removeAll(where: { $0.id == id })
    config.selectedRefinerProfileId = config.refinerProfiles[0].id

    // Best-effort cleanup for the removed profile.
    try? config.deleteLLMAPIKey(profileId: id)

    apiKeyDraft = ""
    apiKeyMessage = nil
  }

  private func makeUniqueProfileName(base: String) -> String {
    let existing = Set(config.refinerProfiles.map { $0.name })
    guard existing.contains(base) else { return base }
    var i = 2
    while true {
      let candidate = "\(base) (\(i))"
      if !existing.contains(candidate) { return candidate }
      i += 1
    }
  }

  func applyBaseURLDefaultForPreset() {
    guard config.refinerProviderFormat == .openAICompatible else { return }
    switch config.refinerOpenAICompatiblePreset {
    case .openai:
      config.refinerBaseURL = PostProcessingConfig.defaultOpenAIBaseURLString
    case .openrouter:
      config.refinerBaseURL = PostProcessingConfig.defaultOpenRouterBaseURLString
    case .custom:
      break
    }
  }

  func applyBaseURLDefaultForFormatIfEmpty() {
    guard config.refinerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    switch config.refinerProviderFormat {
    case .openAICompatible:
      applyBaseURLDefaultForPreset()
      if config.refinerBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        config.refinerBaseURL = PostProcessingConfig.defaultOpenAIBaseURLString
      }
    case .anthropic:
      config.refinerBaseURL = PostProcessingConfig.defaultAnthropicBaseURLString
    }
  }

  func saveAPIKey() {
    let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
      apiKeyMessageIsError = true
      apiKeyMessage = NSLocalizedString("common.error.api_key_empty", comment: "")
      return
    }

    do {
      try config.saveLLMAPIKey(key)
      apiKeyDraft = ""
      apiKeyMessageIsError = false
      let profileName = selectedProfile?.name ?? NSLocalizedString("common.value.unknown", comment: "")
      apiKeyMessage = String(
        format: NSLocalizedString("settings.post_processing.api_key.saved_format", comment: ""),
        profileName
      )
    } catch {
      apiKeyMessageIsError = true
      apiKeyMessage = error.localizedDescription
    }
  }

  func deleteAPIKey() {
    do {
      try config.deleteLLMAPIKey()
      apiKeyDraft = ""
      apiKeyMessageIsError = false
      let profileName = selectedProfile?.name ?? NSLocalizedString("common.value.unknown", comment: "")
      apiKeyMessage = String(
        format: NSLocalizedString("settings.post_processing.api_key.deleted_format", comment: ""),
        profileName
      )
    } catch {
      apiKeyMessageIsError = true
      apiKeyMessage = error.localizedDescription
    }
  }

  func runTest() async {
    isTesting = true
    testMessage = nil
    testMessageIsError = false
    defer { isTesting = false }

    do {
      let client = try LLMAPIClientFactory.create(config: config)
      _ = try await client.refine(
        text: "Test request (no user text stored).",
        systemPrompt: "Reply with the single word OK.",
        timeout: max(0.5, config.refinerTimeout)
      )
      testMessageIsError = false
      testMessage = NSLocalizedString("common.status.success", comment: "")
    } catch let error as LLMAPIError {
      testMessageIsError = true
      switch error {
      case .invalidAPIKey:
        testMessage = NSLocalizedString("common.error.invalid_api_key", comment: "")
      case .timeout:
        testMessage = NSLocalizedString("common.error.timeout", comment: "")
      case .networkError:
        testMessage = error.localizedDescription
      case .apiError:
        testMessage = error.localizedDescription
      default:
        testMessage = error.localizedDescription
      }
    } catch {
      testMessageIsError = true
      testMessage = error.localizedDescription
    }
  }
}
