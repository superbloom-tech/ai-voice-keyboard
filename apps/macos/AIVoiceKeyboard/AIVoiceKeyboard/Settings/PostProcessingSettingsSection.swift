import SwiftUI

struct PostProcessingSettingsSection: View {
  @ObservedObject var model: PostProcessingSettingsModel

  // Keep macOS 13 compatibility while avoiding `onChange(of:)` deprecation warnings on macOS 14+.
  private struct ProviderFormatChangeHandler: ViewModifier {
    @ObservedObject var model: PostProcessingSettingsModel

    func body(content: Content) -> some View {
      if #available(macOS 14.0, *) {
        content.onChange(of: model.config.refinerProviderFormat) { _, _ in
          model.applyBaseURLDefaultForFormatIfEmpty()
        }
      } else {
        content.onChange(of: model.config.refinerProviderFormat) { _ in
          model.applyBaseURLDefaultForFormatIfEmpty()
        }
      }
    }
  }

  private struct PresetChangeHandler: ViewModifier {
    @ObservedObject var model: PostProcessingSettingsModel

    func body(content: Content) -> some View {
      if #available(macOS 14.0, *) {
        content.onChange(of: model.config.refinerOpenAICompatiblePreset) { _, _ in
          model.applyBaseURLDefaultForPreset()
        }
      } else {
        content.onChange(of: model.config.refinerOpenAICompatiblePreset) { _ in
          model.applyBaseURLDefaultForPreset()
        }
      }
    }
  }

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
        // Avoid trimming on each keystroke (can feel odd while typing).
        // Downstream creation (`LLMAPIClientFactory`) still trims for correctness.
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        model.config.refinerModel = trimmed.isEmpty ? nil : newValue
      }
    )
  }

  private var profileNameBinding: Binding<String> {
    Binding(
      get: { model.selectedProfile?.name ?? "" },
      set: { model.updateSelectedProfileName($0) }
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle("settings.post_processing.enabled_toggle", isOn: $model.config.enabled)

      Divider()

      Text("settings.post_processing.cleaner.header")
        .font(.headline)

      Toggle("common.enabled", isOn: $model.config.cleanerEnabled)

      Picker("settings.post_processing.cleaner.rules_preset", selection: $model.config.cleanerRulesRawValue) {
        Text("settings.post_processing.cleaner.rules.basic").tag(TextCleaner.CleaningRules.basic.rawValue)
        Text("settings.post_processing.cleaner.rules.standard").tag(TextCleaner.CleaningRules.standard.rawValue)
        Text("settings.post_processing.cleaner.rules.aggressive").tag(TextCleaner.CleaningRules.aggressive.rawValue)
      }

      HStack {
        Text("common.timeout_seconds")
        Spacer()
        TextField("", value: $model.config.cleanerTimeout, formatter: Self.secondsFormatter)
          .frame(width: 72)
          .multilineTextAlignment(.trailing)
      }

      Divider()

      Text("settings.post_processing.refiner.header")
        .font(.headline)

      HStack(spacing: 12) {
        Picker("settings.post_processing.refiner.profile_picker", selection: $model.config.selectedRefinerProfileId) {
          ForEach(model.config.refinerProfiles, id: \.id) { profile in
            Text(profile.name).tag(profile.id)
          }
        }
        .frame(maxWidth: 320)

        Button("common.action.add") { model.addProfile() }
        Button("common.action.duplicate") { model.duplicateSelectedProfile() }
        Button("common.action.delete") { model.deleteSelectedProfile() }
          .disabled(model.config.refinerProfiles.count <= 1)

        Spacer()
      }

      TextField("settings.post_processing.refiner.profile_name_placeholder", text: profileNameBinding)

      Toggle("common.enabled", isOn: $model.config.refinerEnabled)

      Picker("settings.post_processing.refiner.provider_format", selection: $model.config.refinerProviderFormat) {
        ForEach(LLMProviderFormat.allCases, id: \.self) { format in
          Text(format.displayName).tag(format)
        }
      }
      .modifier(ProviderFormatChangeHandler(model: model))

      if model.config.refinerProviderFormat == .openAICompatible {
        Picker("settings.post_processing.refiner.preset", selection: $model.config.refinerOpenAICompatiblePreset) {
          ForEach(OpenAICompatiblePreset.allCases, id: \.self) { preset in
            Text(preset.displayName).tag(preset)
          }
        }
        .modifier(PresetChangeHandler(model: model))
      }

      TextField("settings.post_processing.refiner.base_url_placeholder", text: $model.config.refinerBaseURL)

      Text("settings.post_processing.refiner.endpoint_hint")
        .font(.footnote)
        .foregroundStyle(.secondary)

      TextField("settings.post_processing.refiner.model_placeholder", text: refinerModelBinding)

      HStack {
        Text("common.timeout_seconds")
        Spacer()
        TextField("", value: $model.config.refinerTimeout, formatter: Self.secondsFormatter)
          .frame(width: 72)
          .multilineTextAlignment(.trailing)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("common.api_key_keychain_title")
          .font(.headline)

        let saved = model.config.hasLLMAPIKey()
        let statusKey = saved ? "common.status.saved" : "common.status.not_saved"
        let profileName = model.selectedProfile?.name ?? NSLocalizedString("common.value.unknown", comment: "")
        let statusLine = String(
          format: NSLocalizedString("settings.post_processing.api_key.status_format", comment: ""),
          NSLocalizedString(statusKey, comment: ""),
          profileName
        )
        Text(statusLine)
          .font(.footnote)
          .foregroundStyle(saved ? .primary : .secondary)

        HStack(spacing: 12) {
          SecureField("common.api_key_enter_placeholder", text: $model.apiKeyDraft)
          Button("common.action.save") { model.saveAPIKey() }
          Button("common.action.delete") { model.deleteAPIKey() }
        }

        if let message = model.apiKeyMessage, !message.isEmpty {
          Text(message)
            .font(.footnote)
            .foregroundStyle(model.apiKeyMessageIsError ? .red : .secondary)
        }
      }

      Divider()

      Text("settings.post_processing.fallback.header")
        .font(.headline)

      Picker("settings.post_processing.fallback.behavior_picker", selection: $model.config.fallbackBehaviorRawValue) {
        Text("settings.post_processing.fallback.behavior.return_original").tag(0)
        Text("settings.post_processing.fallback.behavior.return_last_valid").tag(1)
        Text("settings.post_processing.fallback.behavior.throw_error").tag(2)
      }

      Divider()

      HStack(spacing: 12) {
        Button(model.isTesting ? LocalizedStringKey("common.status.testing") : LocalizedStringKey("common.action.test")) {
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

      Text("settings.post_processing.privacy_hint")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }
}
