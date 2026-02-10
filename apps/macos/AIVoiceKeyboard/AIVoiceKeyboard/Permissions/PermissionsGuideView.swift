import SwiftUI
import VoiceKeyboardCore

/// First-launch (and on-demand) guide that explains required permissions and provides shortcuts
/// to request permissions / open System Settings / refresh status.
struct PermissionsGuideView: View {
  @StateObject private var permissions = PermissionCenter()

  let onDone: () -> Void

  private var sttProviderName: String {
    switch STTProviderStore.load() {
    case .appleSpeech:
      return "Apple Speech"
    case .whisperLocal:
      return "Whisper (Local)"
    case .openAICompatible:
      return "Remote (OpenAI-compatible)"
    }
  }

  private var requiresSpeechRecognition: Bool {
    if case .appleSpeech = STTProviderStore.load() { return true }
    return false
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text("Permissions Guide")
          .font(.title2)

        Text("To record and insert text into other apps, AI Voice Keyboard needs a few macOS permissions.")
          .foregroundStyle(.secondary)

        Text("Current STT provider: \(sttProviderName)")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      GroupBox("Required") {
        VStack(alignment: .leading, spacing: 12) {
          PermissionGuideRow(
            kind: .microphone,
            status: permissions.statuses[.microphone] ?? .unknown,
            requiredLabel: "Required",
            description: "Needed to record audio.",
            onRequest: { await permissions.request(.microphone) },
            onOpenSystemSettings: { PermissionChecks.openSystemSettings(for: .microphone) },
            onRefresh: { permissions.refresh() }
          )

          PermissionGuideRow(
            kind: .speechRecognition,
            status: permissions.statuses[.speechRecognition] ?? .unknown,
            requiredLabel: requiresSpeechRecognition ? "Required" : "Optional",
            description: requiresSpeechRecognition
              ? "Required when using Apple Speech."
              : "Only required for Apple Speech. Whisper/Remote do not need this permission.",
            onRequest: { await permissions.request(.speechRecognition) },
            onOpenSystemSettings: { PermissionChecks.openSystemSettings(for: .speechRecognition) },
            onRefresh: { permissions.refresh() }
          )
        }
        .padding(.top, 6)
      }

      GroupBox("Auto-insert (Recommended)") {
        VStack(alignment: .leading, spacing: 10) {
          PermissionGuideRow(
            kind: .accessibility,
            status: permissions.statuses[.accessibility] ?? .unknown,
            requiredLabel: "Recommended",
            description: "Enables auto-insert into other apps. Without it, we will copy text to clipboard and you can press Cmd+V to paste.",
            onRequest: { await permissions.request(.accessibility) },
            onOpenSystemSettings: { PermissionChecks.openSystemSettings(for: .accessibility) },
            onRefresh: { permissions.refresh() }
          )

          Text("Tip: Accessibility is a trust setting. After enabling it in System Settings, return to this app and click Refresh.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
      }

      HStack {
        Button("Refresh") { permissions.refresh() }
        Spacer()
        Button("Done") { onDone() }
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 640, height: 520)
    .onAppear {
      permissions.refresh()
    }
  }
}

private struct PermissionGuideRow: View {
  let kind: PermissionKind
  let status: PermissionStatus

  let requiredLabel: String
  let description: String

  let onRequest: () async -> Void
  let onOpenSystemSettings: () -> Void
  let onRefresh: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 12) {
        Text(kind.displayName)
          .frame(width: 160, alignment: .leading)

        Text(statusText)
          .foregroundStyle(status.isSatisfied ? .green : .secondary)
          .frame(width: 140, alignment: .leading)

        Text(requiredLabel)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        Spacer()

        actionButtons
      }

      Text(description)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.leading, 172)
    }
  }

  @ViewBuilder
  private var actionButtons: some View {
    if kind == .accessibility {
      if status.isSatisfied {
        Text("OK")
          .foregroundStyle(.secondary)
      } else {
        Button("Prompt") { Task { await onRequest() } }
        Button("Open System Settings") { onOpenSystemSettings() }
      }
    } else {
      if status == .notDetermined {
        Button("Request") { Task { await onRequest() } }
      } else if status == .denied || status == .restricted {
        Button("Open System Settings") { onOpenSystemSettings() }
      } else if status == .authorized {
        Text("OK")
          .foregroundStyle(.secondary)
      } else {
        Button("Refresh") { onRefresh() }
        Button("Open System Settings") { onOpenSystemSettings() }
      }
    }
  }

  private var statusText: String {
    if kind == .accessibility {
      return status.isSatisfied ? "Trusted" : "Not Trusted"
    }
    if status == .unknown {
      return "Unknown (Refresh)"
    }
    return status.displayText
  }
}
