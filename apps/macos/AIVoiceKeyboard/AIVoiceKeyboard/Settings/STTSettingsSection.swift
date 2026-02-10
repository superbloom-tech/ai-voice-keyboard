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
      Picker("Provider", selection: $model.selectedProvider) {
        ForEach(STTProviderKind.allCases) { kind in
          Text(kind.displayName).tag(kind)
        }
      }

      Divider()

      switch model.selectedProvider {
      case .appleSpeech:
        Text("Apple Speech")
          .font(.headline)

        TextField("Locale identifier (optional, e.g. en_US, zh_CN)", text: $model.appleSpeechLocaleIdentifier)

        Text("Requires macOS Speech Recognition permission.")
          .font(.footnote)
          .foregroundStyle(.secondary)

      case .whisperLocal:
        Text("Whisper (Local CLI)")
          .font(.headline)

        TextField("Whisper executable path (optional)", text: $model.whisperExecutablePath)

        TextField("Model (e.g. turbo, base, small)", text: $model.whisperModel)

        TextField("Language (optional, e.g. en, zh)", text: $model.whisperLanguage)

        HStack {
          Text("Timeout (seconds)")
          Spacer()
          TextField("", value: $model.whisperTimeoutSeconds, formatter: Self.secondsFormatter)
            .frame(width: 72)
            .multilineTextAlignment(.trailing)
        }

        Text("Install: `brew install openai-whisper` (provides the `whisper` CLI). First run may download model files and take longer.")
          .font(.footnote)
          .foregroundStyle(.secondary)

      case .openAICompatible:
        Text("Remote (OpenAI-compatible)")
          .font(.headline)

        HStack(spacing: 12) {
          TextField("Base URL (e.g. https://api.openai.com/v1)", text: $model.remoteBaseURLString)
          Button("Reset") { model.applyDefaultRemoteBaseURL() }
        }

        TextField("Model (e.g. whisper-1)", text: $model.remoteModel)

        HStack(spacing: 12) {
          TextField("API Key ID (Keychain key)", text: $model.remoteApiKeyId)
          Button("Default") { model.remoteApiKeyId = "openai" }
        }

        HStack {
          Text("Timeout (seconds)")
          Spacer()
          TextField("", value: $model.remoteTimeoutSeconds, formatter: Self.secondsFormatter)
            .frame(width: 72)
            .multilineTextAlignment(.trailing)
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("API Key (Keychain)")
            .font(.headline)

          Text("Status: \(model.hasRemoteAPIKey ? "Saved" : "Not saved") (ID: \(model.remoteApiKeyId.trimmingCharacters(in: .whitespacesAndNewlines)))")
            .font(.footnote)
            .foregroundStyle(model.hasRemoteAPIKey ? .green : .secondary)

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

        Text("Privacy: audio is sent to the configured provider.")
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

