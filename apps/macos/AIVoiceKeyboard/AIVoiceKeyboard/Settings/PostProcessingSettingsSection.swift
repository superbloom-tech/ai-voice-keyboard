import SwiftUI

struct PostProcessingSettingsSection: View {
  @ObservedObject var model: PostProcessingSettingsModel

  private static let secondsFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.minimum = 0
    f.maximumFractionDigits = 1
    return f
  }()

  private var refinerModelBinding: Binding<String> {
    Binding(
      get: { model.config.refinerModel ?? "" },
      set: { newValue in
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        model.config.refinerModel = trimmed.isEmpty ? nil : trimmed
      }
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle("Post-processing Enabled", isOn: $model.config.enabled)

      Divider()

      Text("Cleaner")
        .font(.headline)

      Toggle("Enabled", isOn: $model.config.cleanerEnabled)

      Picker("Rules preset", selection: $model.config.cleanerRulesRawValue) {
        Text("Basic").tag(TextCleaner.CleaningRules.basic.rawValue)
        Text("Standard").tag(TextCleaner.CleaningRules.standard.rawValue)
        Text("Aggressive").tag(TextCleaner.CleaningRules.aggressive.rawValue)
      }

      HStack {
        Text("Timeout (seconds)")
        Spacer()
        TextField("", value: $model.config.cleanerTimeout, formatter: Self.secondsFormatter)
          .frame(width: 72)
          .multilineTextAlignment(.trailing)
      }

      Divider()

      Text("LLM Refiner")
        .font(.headline)

      Toggle("Enabled", isOn: $model.config.refinerEnabled)

      Picker("Provider format", selection: $model.config.refinerProviderFormat) {
        ForEach(LLMProviderFormat.allCases, id: \.self) { format in
          Text(format.displayName).tag(format)
        }
      }
      .onChange(of: model.config.refinerProviderFormat) { _ in
        model.applyBaseURLDefaultForFormatIfEmpty()
      }

      if model.config.refinerProviderFormat == .openAICompatible {
        Picker("Preset", selection: $model.config.refinerOpenAICompatiblePreset) {
          ForEach(OpenAICompatiblePreset.allCases, id: \.self) { preset in
            Text(preset.displayName).tag(preset)
          }
        }
        .onChange(of: model.config.refinerOpenAICompatiblePreset) { _ in
          model.applyBaseURLDefaultForPreset()
        }
      }

      TextField("Base URL (e.g. https://api.openai.com/v1)", text: $model.config.refinerBaseURL)

      Text("Endpoint is appended automatically: OpenAI-compatible => /chat/completions, Anthropic => /messages")
        .font(.footnote)
        .foregroundStyle(.secondary)

      TextField("Model", text: refinerModelBinding)

      HStack {
        Text("Timeout (seconds)")
        Spacer()
        TextField("", value: $model.config.refinerTimeout, formatter: Self.secondsFormatter)
          .frame(width: 72)
          .multilineTextAlignment(.trailing)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("API Key (Keychain)")
          .font(.headline)

        let saved = model.config.hasLLMAPIKey()
        Text("Status: \(saved ? "Saved" : "Not saved") (\(model.config.llmAPIKeyNamespace))")
          .font(.footnote)
          .foregroundStyle(saved ? .green : .secondary)

        HStack(spacing: 12) {
          SecureField("Enter new API key", text: $model.apiKeyDraft)
          Button("Save") { model.saveAPIKey() }
          Button("Delete") { model.deleteAPIKey() }
        }

        if let message = model.apiKeyMessage, !message.isEmpty {
          Text(message)
            .font(.footnote)
            .foregroundStyle(model.apiKeyMessageIsError ? .red : .secondary)
        }
      }

      Divider()

      Text("Fallback")
        .font(.headline)

      Picker("Behavior", selection: $model.config.fallbackBehaviorRawValue) {
        Text("Return original").tag(0)
        Text("Return last valid").tag(1)
        Text("Throw error").tag(2)
      }

      Divider()

      HStack(spacing: 12) {
        Button(model.isTesting ? "Testing..." : "Test") {
          Task { await model.runTest() }
        }
        .disabled(model.isTesting)

        if model.isTesting {
          ProgressView()
            .scaleEffect(0.7)
        }

        Spacer()
      }

      if let message = model.testMessage, !message.isEmpty {
        Text(message)
          .font(.footnote)
          .foregroundStyle(model.testMessageIsError ? .red : .secondary)
      }

      Text("Privacy: Refiner sends text to the selected third-party provider.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }
}
