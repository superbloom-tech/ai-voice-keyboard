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
    PreferencesPane {
      PreferencesGroupBox {
        Toggle("settings.post_processing.enabled_toggle", isOn: $model.config.enabled)
      }

      let postProcessingEnabled = model.config.enabled
      // When post-processing is disabled, keep advanced settings visible but non-interactive
      // (and visually de-emphasized) to avoid confusing "editable but inactive" states.
      Group {
        PreferencesGroupBox("settings.post_processing.cleaner.header") {
          Toggle("common.enabled", isOn: $model.config.cleanerEnabled)

          Picker("settings.post_processing.cleaner.rules_preset", selection: $model.config.cleanerRulesRawValue) {
            Text("settings.post_processing.cleaner.rules.basic").tag(TextCleaner.CleaningRules.basic.rawValue)
            Text("settings.post_processing.cleaner.rules.standard").tag(TextCleaner.CleaningRules.standard.rawValue)
            Text("settings.post_processing.cleaner.rules.aggressive").tag(TextCleaner.CleaningRules.aggressive.rawValue)
          }
          .pickerStyle(.menu)

          LabeledContent("common.timeout_seconds") {
            TextField("", value: $model.config.cleanerTimeout, formatter: Self.secondsFormatter)
              .textFieldStyle(.roundedBorder)
              .frame(width: 96)
              .multilineTextAlignment(.trailing)
          }
        }

        PreferencesGroupBox("settings.post_processing.refiner.header") {
          LabeledContent("settings.post_processing.refiner.profile_picker") {
            HStack(spacing: 10) {
              Picker("", selection: $model.config.selectedRefinerProfileId) {
                ForEach(model.config.refinerProfiles, id: \.id) { profile in
                  Text(profile.name).tag(profile.id)
                }
              }
              .labelsHidden()
              .pickerStyle(.menu)
              .frame(maxWidth: 320)

              ControlGroup {
                Button("common.action.add") { model.addProfile() }
                Button("common.action.duplicate") { model.duplicateSelectedProfile() }
                Button("common.action.delete") { model.deleteSelectedProfile() }
                  .disabled(model.config.refinerProfiles.count <= 1)
              }
            }
          }

          TextField("settings.post_processing.refiner.profile_name_placeholder", text: profileNameBinding)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 360)

          Toggle("common.enabled", isOn: $model.config.refinerEnabled)

          Picker("settings.post_processing.refiner.provider_format", selection: $model.config.refinerProviderFormat) {
            ForEach(LLMProviderFormat.allCases, id: \.self) { format in
              Text(format.displayName).tag(format)
            }
          }
          .pickerStyle(.menu)
          .modifier(ProviderFormatChangeHandler(model: model))

          if model.config.refinerProviderFormat == .openAICompatible {
            Picker("settings.post_processing.refiner.preset", selection: $model.config.refinerOpenAICompatiblePreset) {
              ForEach(OpenAICompatiblePreset.allCases, id: \.self) { preset in
                Text(preset.displayName).tag(preset)
              }
            }
            .pickerStyle(.menu)
            .modifier(PresetChangeHandler(model: model))
          }

          TextField("settings.post_processing.refiner.base_url_placeholder", text: $model.config.refinerBaseURL)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 360)

          PreferencesFootnote("settings.post_processing.refiner.endpoint_hint")

          TextField("settings.post_processing.refiner.model_placeholder", text: refinerModelBinding)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 360)

          LabeledContent("common.timeout_seconds") {
            TextField("", value: $model.config.refinerTimeout, formatter: Self.secondsFormatter)
              .textFieldStyle(.roundedBorder)
              .frame(width: 96)
              .multilineTextAlignment(.trailing)
          }
        }

        PreferencesGroupBox("common.api_key_keychain_title") {
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

          HStack(spacing: 10) {
            SecureField("common.api_key_enter_placeholder", text: $model.apiKeyDraft)
              .textFieldStyle(.roundedBorder)
              .frame(maxWidth: 360)

            ControlGroup {
              Button("common.action.save") { model.saveAPIKey() }
              Button("common.action.delete") { model.deleteAPIKey() }
            }
          }

          if let message = model.apiKeyMessage, !message.isEmpty {
            Text(message)
              .font(.footnote)
              .foregroundStyle(model.apiKeyMessageIsError ? .red : .secondary)
          }
        }

        PreferencesGroupBox("settings.post_processing.fallback.header") {
          Picker("settings.post_processing.fallback.behavior_picker", selection: $model.config.fallbackBehaviorRawValue) {
            Text("settings.post_processing.fallback.behavior.return_original").tag(0)
            Text("settings.post_processing.fallback.behavior.return_last_valid").tag(1)
            Text("settings.post_processing.fallback.behavior.throw_error").tag(2)
          }
          .pickerStyle(.menu)
        }

        PreferencesGroupBox("common.action.test") {
          HStack(spacing: 10) {
            Button(model.isTesting ? LocalizedStringKey("common.status.testing") : LocalizedStringKey("common.action.test")) {
              Task { await model.runTest() }
            }
            .disabled(model.isTesting)

            if model.isTesting {
              ProgressView()
                .scaleEffect(0.7)
            }
          }

          if let message = model.testMessage, !message.isEmpty {
            Text(message)
              .font(.footnote)
              .foregroundStyle(model.testMessageIsError ? .red : .secondary)
          }

          PreferencesFootnote("settings.post_processing.privacy_hint")
        }
      }
      .disabled(!postProcessingEnabled)
      .opacity(postProcessingEnabled ? 1.0 : 0.45)
    }
  }
}
