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

    // Avoid rebuilding the pipeline on every keystroke while editing Base URL / Model.
    $config
      .dropFirst()
      .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
      .sink { config in
        config.save()
      }
      .store(in: &cancellables)
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
      apiKeyMessage = "API key cannot be empty."
      return
    }

    do {
      try config.saveLLMAPIKey(key)
      apiKeyDraft = ""
      apiKeyMessageIsError = false
      apiKeyMessage = "API key saved (\(config.llmAPIKeyNamespace))."
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
      apiKeyMessage = "API key deleted (\(config.llmAPIKeyNamespace))."
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
      testMessage = "Success."
    } catch let error as LLMAPIError {
      testMessageIsError = true
      switch error {
      case .invalidAPIKey:
        testMessage = "Invalid API key."
      case .timeout:
        testMessage = "Timeout."
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

