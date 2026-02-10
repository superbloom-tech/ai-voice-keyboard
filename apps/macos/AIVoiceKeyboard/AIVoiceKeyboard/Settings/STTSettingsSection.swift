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
    VStack(alignment: .leading, spacing: 12) {
      Picker("settings.stt.provider_label", selection: $model.selectedProvider) {
        ForEach(STTProviderKind.allCases) { kind in
          Text(kind.displayName).tag(kind)
        }
      }

      Divider()

      switch model.selectedProvider {
      case .appleSpeech:
        Text("stt_provider.apple_speech")
          .font(.headline)

        TextField("settings.stt.apple_speech.locale_identifier_placeholder", text: $model.appleSpeechLocaleIdentifier)

        Text("settings.stt.apple_speech.permission_hint")
          .font(.footnote)
          .foregroundStyle(.secondary)

      case .whisperLocal:
        Text("stt_provider.whisper_local")
          .font(.headline)

        TextField("settings.stt.whisper.executable_path_placeholder", text: $model.whisperExecutablePath)

        TextField("settings.stt.whisper.model_placeholder", text: $model.whisperModel)

        TextField("settings.stt.whisper.language_placeholder", text: $model.whisperLanguage)

        HStack {
          Text("common.timeout_seconds")
          Spacer()
          TextField("", value: $model.whisperTimeoutSeconds, formatter: Self.secondsFormatter)
            .frame(width: 72)
            .multilineTextAlignment(.trailing)
        }

        Text("settings.stt.whisper.install_hint")
          .font(.footnote)
          .foregroundStyle(.secondary)

      case .openAICompatible:
        Text("stt_provider.openai_compatible")
          .font(.headline)

        HStack(spacing: 12) {
          TextField("settings.stt.remote.base_url_placeholder", text: $model.remoteBaseURLString)
          Button("common.action.reset") { model.applyDefaultRemoteBaseURL() }
        }

        TextField("settings.stt.remote.model_placeholder", text: $model.remoteModel)

        HStack(spacing: 12) {
          TextField("settings.stt.remote.api_key_id_placeholder", text: $model.remoteApiKeyId)
          Button("common.action.default") { model.remoteApiKeyId = "openai" }
        }

        HStack {
          Text("common.timeout_seconds")
          Spacer()
          TextField("", value: $model.remoteTimeoutSeconds, formatter: Self.secondsFormatter)
            .frame(width: 72)
            .multilineTextAlignment(.trailing)
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("common.api_key_keychain_title")
            .font(.headline)

          let statusKey = model.hasRemoteAPIKey ? "common.status.saved" : "common.status.not_saved"
          let statusLine = String(
            format: NSLocalizedString("settings.stt.remote.api_key.status_format", comment: ""),
            NSLocalizedString(statusKey, comment: ""),
            model.remoteApiKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
          )
          Text(statusLine)
            .font(.footnote)
            .foregroundStyle(model.hasRemoteAPIKey ? .green : .secondary)

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

        Text("settings.stt.remote.privacy_hint")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if let message = model.configMessage, !message.isEmpty {
        Text(message)
          .font(.footnote)
          .foregroundStyle(model.configMessageIsError ? .red : .secondary)
      }
    }
  }
}
