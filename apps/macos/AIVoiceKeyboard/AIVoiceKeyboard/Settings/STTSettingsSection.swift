import SwiftUI

struct STTSettingsSection: View {
  @ObservedObject var model: STTSettingsModel

  private static let secondsFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.minimumFractionDigits = 0
    f.maximumFractionDigits = 1
    return f
  }()

  var body: some View {
    PreferencesPane {
      PreferencesGroupBox("settings.stt.provider_label") {
        Picker("settings.stt.provider_label", selection: $model.selectedProvider) {
          ForEach(STTProviderKind.allCases) { kind in
            Text(kind.displayName).tag(kind)
          }
        }
        .pickerStyle(.menu)
      }

      switch model.selectedProvider {
      case .appleSpeech:
        PreferencesGroupBox("stt_provider.apple_speech") {
          TextField("settings.stt.apple_speech.locale_identifier_placeholder", text: $model.appleSpeechLocaleIdentifier)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 360)

          PreferencesFootnote("settings.stt.apple_speech.permission_hint")
        }

      case .whisperLocal:
        PreferencesGroupBox("stt_provider.whisper_local") {
          TextField("settings.stt.whisper.executable_path_placeholder", text: $model.whisperExecutablePath)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 360)

          TextField("settings.stt.whisper.model_placeholder", text: $model.whisperModel)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 360)

          TextField("settings.stt.whisper.language_placeholder", text: $model.whisperLanguage)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 360)

          LabeledContent("common.timeout_seconds") {
            TextField("", value: $model.whisperTimeoutSeconds, formatter: Self.secondsFormatter)
              .textFieldStyle(.roundedBorder)
              .frame(width: 96)
              .multilineTextAlignment(.trailing)
          }

          PreferencesFootnote("settings.stt.whisper.install_hint")
        }

      case .openAICompatible:
        PreferencesGroupBox("stt_provider.openai_compatible") {
          LabeledContent("settings.stt.remote.base_url_placeholder") {
            HStack(spacing: 10) {
              TextField("", text: $model.remoteBaseURLString)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
              Button("common.action.reset") { model.applyDefaultRemoteBaseURL() }
            }
          }

          TextField("settings.stt.remote.model_placeholder", text: $model.remoteModel)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 360)

          LabeledContent("settings.stt.remote.api_key_id_placeholder") {
            HStack(spacing: 10) {
              TextField("", text: $model.remoteApiKeyId)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
              Button("common.action.default") { model.remoteApiKeyId = "openai" }
            }
          }

          LabeledContent("common.timeout_seconds") {
            TextField("", value: $model.remoteTimeoutSeconds, formatter: Self.secondsFormatter)
              .textFieldStyle(.roundedBorder)
              .frame(width: 96)
              .multilineTextAlignment(.trailing)
          }
        }

        PreferencesGroupBox("common.api_key_keychain_title") {
          let statusKey = model.hasRemoteAPIKey ? "common.status.saved" : "common.status.not_saved"
          let statusLine = String(
            format: NSLocalizedString("settings.stt.remote.api_key.status_format", comment: ""),
            NSLocalizedString(statusKey, comment: ""),
            model.remoteApiKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
          )

          Text(statusLine)
            .font(.footnote)
            .foregroundStyle(model.hasRemoteAPIKey ? .primary : .secondary)

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

          PreferencesFootnote("settings.stt.remote.privacy_hint")
        }

      case .elevenLabsREST:
        PreferencesGroupBox("stt_provider.elevenlabs_rest") {
          LabeledContent("settings.stt.remote.base_url_placeholder") {
            HStack(spacing: 10) {
              TextField("", text: $model.elevenLabsBaseURLString)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
              Button("common.action.reset") { model.applyDefaultElevenLabsBaseURL() }
            }
          }

          TextField("settings.stt.remote.model_placeholder", text: $model.elevenLabsModel)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 360)

          LabeledContent("settings.stt.remote.api_key_id_placeholder") {
            HStack(spacing: 10) {
              TextField("", text: $model.elevenLabsApiKeyId)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
              Button("common.action.default") { model.elevenLabsApiKeyId = "elevenlabs" }
            }
          }

          LabeledContent("common.timeout_seconds") {
            TextField("", value: $model.elevenLabsTimeoutSeconds, formatter: Self.secondsFormatter)
              .textFieldStyle(.roundedBorder)
              .frame(width: 96)
              .multilineTextAlignment(.trailing)
          }
        }

        PreferencesGroupBox("common.api_key_keychain_title") {
          let statusKey = model.hasElevenLabsAPIKey ? "common.status.saved" : "common.status.not_saved"
          let statusLine = String(
            format: NSLocalizedString("settings.stt.remote.api_key.status_format", comment: ""),
            NSLocalizedString(statusKey, comment: ""),
            model.elevenLabsApiKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
          )

          Text(statusLine)
            .font(.footnote)
            .foregroundStyle(model.hasElevenLabsAPIKey ? .primary : .secondary)

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

          PreferencesFootnote("settings.stt.remote.privacy_hint")
        }
      }

      if let message = model.configMessage, !message.isEmpty {
        PreferencesGroupBox {
          Text(message)
            .font(.footnote)
            .foregroundStyle(model.configMessageIsError ? .red : .secondary)
        }
      }
    }
  }
}
