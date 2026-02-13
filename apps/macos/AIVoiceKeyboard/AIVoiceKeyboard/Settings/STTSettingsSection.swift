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
    Form {
      Section {
        Picker("settings.stt.provider_label", selection: $model.selectedProvider) {
          ForEach(STTProviderKind.allCases) { kind in
            Text(kind.displayName).tag(kind)
          }
        }
      }

      switch model.selectedProvider {
      case .appleSpeech:
        Section(header: Text(model.selectedProvider.displayName)) {
          TextField("settings.stt.apple_speech.locale_identifier_placeholder", text: $model.appleSpeechLocaleIdentifier)

          Text("settings.stt.apple_speech.permission_hint")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

      case .whisperLocal:
        Section(header: Text(model.selectedProvider.displayName)) {
          TextField("settings.stt.whisper.executable_path_placeholder", text: $model.whisperExecutablePath)

          TextField("settings.stt.whisper.model_placeholder", text: $model.whisperModel)

          TextField("settings.stt.whisper.language_placeholder", text: $model.whisperLanguage)

          LabeledContent("common.timeout_seconds") {
            TextField("", value: $model.whisperTimeoutSeconds, formatter: Self.secondsFormatter)
              .frame(width: 72)
              .multilineTextAlignment(.trailing)
          }

          Text("settings.stt.whisper.install_hint")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

      case .openAICompatible:
        Section(header: Text(model.selectedProvider.displayName)) {
          LabeledContent("settings.stt.remote.base_url_placeholder") {
            HStack(spacing: 10) {
              TextField("", text: $model.remoteBaseURLString)
              Button("common.action.reset") { model.applyDefaultRemoteBaseURL() }
            }
          }

          TextField("settings.stt.remote.model_placeholder", text: $model.remoteModel)

          LabeledContent("settings.stt.remote.api_key_id_placeholder") {
            HStack(spacing: 10) {
              TextField("", text: $model.remoteApiKeyId)
              Button("common.action.default") { model.remoteApiKeyId = "openai" }
            }
          }

          LabeledContent("common.timeout_seconds") {
            TextField("", value: $model.remoteTimeoutSeconds, formatter: Self.secondsFormatter)
              .frame(width: 72)
              .multilineTextAlignment(.trailing)
          }
        }

        Section("common.api_key_keychain_title") {
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
            Button("common.action.save") { model.saveAPIKey() }
            Button("common.action.delete") { model.deleteAPIKey() }
          }

          if let message = model.apiKeyMessage, !message.isEmpty {
            Text(message)
              .font(.footnote)
              .foregroundStyle(model.apiKeyMessageIsError ? .red : .secondary)
          }

          Text("settings.stt.remote.privacy_hint")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

      case .elevenLabsREST:
        Section(header: Text(model.selectedProvider.displayName)) {
          LabeledContent("settings.stt.remote.base_url_placeholder") {
            HStack(spacing: 10) {
              TextField("", text: $model.elevenLabsBaseURLString)
              Button("common.action.reset") { model.applyDefaultElevenLabsBaseURL() }
            }
          }

          TextField("settings.stt.remote.model_placeholder", text: $model.elevenLabsModel)

          LabeledContent("settings.stt.remote.api_key_id_placeholder") {
            HStack(spacing: 10) {
              TextField("", text: $model.elevenLabsApiKeyId)
              Button("common.action.default") { model.elevenLabsApiKeyId = "elevenlabs" }
            }
          }

          LabeledContent("common.timeout_seconds") {
            TextField("", value: $model.elevenLabsTimeoutSeconds, formatter: Self.secondsFormatter)
              .frame(width: 72)
              .multilineTextAlignment(.trailing)
          }
        }

        Section("common.api_key_keychain_title") {
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
            Button("common.action.save") { model.saveAPIKey() }
            Button("common.action.delete") { model.deleteAPIKey() }
          }

          if let message = model.apiKeyMessage, !message.isEmpty {
            Text(message)
              .font(.footnote)
              .foregroundStyle(model.apiKeyMessageIsError ? .red : .secondary)
          }

          Text("settings.stt.remote.privacy_hint")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

      if let message = model.configMessage, !message.isEmpty {
        Section {
          Text(message)
            .font(.footnote)
            .foregroundStyle(model.configMessageIsError ? .red : .secondary)
        }
      }
    }
  }
}
