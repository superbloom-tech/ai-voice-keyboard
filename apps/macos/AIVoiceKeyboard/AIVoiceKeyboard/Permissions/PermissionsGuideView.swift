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
      return NSLocalizedString("stt_provider.apple_speech", comment: "")
    case .whisperLocal:
      return NSLocalizedString("stt_provider.whisper_local", comment: "")
    case .openAICompatible:
      return NSLocalizedString("stt_provider.openai_compatible", comment: "")
    }
  }

  private var requiresSpeechRecognition: Bool {
    if case .appleSpeech = STTProviderStore.load() { return true }
    return false
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text("permissions_guide.title")
          .font(.title2)

        Text("permissions_guide.subtitle")
          .foregroundStyle(.secondary)

        HStack(spacing: 6) {
          Text("permissions_guide.current_provider_label")
            .font(.footnote)
            .foregroundStyle(.secondary)

          Text(sttProviderName)
            .font(.footnote)
            .foregroundStyle(.secondary)

          Image(systemName: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .help(Text("permissions_guide.current_provider_help"))
        }
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          PermissionGuideRow(
            kind: .microphone,
            status: permissions.statuses[.microphone] ?? .unknown,
            tag: "permissions_guide.tag.required",
            help: "permissions_guide.help.microphone",
            onRequest: { await permissions.request(.microphone) },
            onOpenSystemSettings: { PermissionChecks.openSystemSettings(for: .microphone) },
            onRefresh: { permissions.refresh() }
          )

          PermissionGuideRow(
            kind: .speechRecognition,
            status: permissions.statuses[.speechRecognition] ?? .unknown,
            tag: requiresSpeechRecognition ? "permissions_guide.tag.required" : "permissions_guide.tag.optional",
            help: requiresSpeechRecognition ? "permissions_guide.help.speech_required" : "permissions_guide.help.speech_optional",
            onRequest: { await permissions.request(.speechRecognition) },
            onOpenSystemSettings: { PermissionChecks.openSystemSettings(for: .speechRecognition) },
            onRefresh: { permissions.refresh() }
          )
        }
        .padding(.top, 6)
      }

      .groupBoxStyle(GuideSectionGroupBoxStyle(titleKey: "permissions_guide.section.required"))

      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          PermissionGuideRow(
            kind: .accessibility,
            status: permissions.statuses[.accessibility] ?? .unknown,
            tag: "permissions_guide.tag.recommended",
            help: "permissions_guide.help.accessibility",
            onRequest: { await permissions.request(.accessibility) },
            onOpenSystemSettings: { PermissionChecks.openSystemSettings(for: .accessibility) },
            onRefresh: { permissions.refresh() }
          )

          Text("permissions_guide.tip.accessibility_trust")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
      }
      .groupBoxStyle(GuideSectionGroupBoxStyle(titleKey: "permissions_guide.section.auto_insert"))

      HStack {
        Button("permissions_guide.action.refresh") { permissions.refresh() }
        Spacer()
        Button("permissions_guide.action.done") { onDone() }
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

  let tag: LocalizedStringKey
  let help: LocalizedStringKey

  let onRequest: () async -> Void
  let onOpenSystemSettings: () -> Void
  let onRefresh: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: kind.systemImageName)
        .foregroundStyle(.secondary)

      Text(kind.titleKey)
        .frame(width: 170, alignment: .leading)

      Text(statusText)
        .foregroundStyle(status.isSatisfied ? .green : .secondary)
        .frame(width: 140, alignment: .leading)

      Text(tag)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))

      Image(systemName: "info.circle")
        .foregroundStyle(.secondary)
        .help(Text(help))

      Spacer()

      actionButtons
    }
  }

  @ViewBuilder
  private var actionButtons: some View {
    if kind == .accessibility {
      if status.isSatisfied {
        Text("permissions_guide.status.ok")
          .foregroundStyle(.secondary)
      } else {
        Button("permissions_guide.action.prompt") { Task { await onRequest() } }
        Button("permissions_guide.action.open_system_settings") { onOpenSystemSettings() }
      }
    } else {
      if status == .notDetermined {
        Button("permissions_guide.action.request") { Task { await onRequest() } }
      } else if status == .denied || status == .restricted {
        Button("permissions_guide.action.open_system_settings") { onOpenSystemSettings() }
      } else if status == .authorized {
        Text("permissions_guide.status.ok")
          .foregroundStyle(.secondary)
      } else {
        Button("permissions_guide.action.refresh") { onRefresh() }
        Button("permissions_guide.action.open_system_settings") { onOpenSystemSettings() }
      }
    }
  }

  private var statusText: String {
    if kind == .accessibility {
      return status.isSatisfied
        ? NSLocalizedString("permission.status.trusted", comment: "")
        : NSLocalizedString("permission.status.not_trusted", comment: "")
    }
    if status == .unknown {
      return NSLocalizedString("permission.status.unknown", comment: "")
    }
    switch status {
    case .authorized:
      return NSLocalizedString("permission.status.authorized", comment: "")
    case .denied:
      return NSLocalizedString("permission.status.denied", comment: "")
    case .notDetermined:
      return NSLocalizedString("permission.status.not_determined", comment: "")
    case .restricted:
      return NSLocalizedString("permission.status.restricted", comment: "")
    case .unknown:
      return NSLocalizedString("permission.status.unknown", comment: "")
    }
  }
}

private struct GuideSectionGroupBoxStyle: GroupBoxStyle {
  let titleKey: LocalizedStringKey

  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(titleKey)
        .font(.headline)

      configuration.content
    }
    .padding(12)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.06))
    )
  }
}

private extension PermissionKind {
  var titleKey: LocalizedStringKey {
    switch self {
    case .microphone:
      return "permission.kind.microphone"
    case .speechRecognition:
      return "permission.kind.speech_recognition"
    case .accessibility:
      return "permission.kind.accessibility"
    }
  }

  var systemImageName: String {
    switch self {
    case .microphone:
      return "mic.fill"
    case .speechRecognition:
      return "waveform"
    case .accessibility:
      return "figure.roll"
    }
  }
}
