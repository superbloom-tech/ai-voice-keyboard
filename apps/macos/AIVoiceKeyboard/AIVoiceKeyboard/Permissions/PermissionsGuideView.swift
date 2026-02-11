import SwiftUI
import VoiceKeyboardCore

/// First-launch (and on-demand) guide that explains required permissions and provides shortcuts
/// to request permissions / open System Settings / refresh status.
struct PermissionsGuideView: View {
  @StateObject private var permissions = PermissionCenter()
  @State private var providerConfig: STTProviderConfiguration = STTProviderStore.load()
  @State private var showProviderHelpPopover = false

  let onDone: () -> Void

  private var sttProviderName: String {
    switch providerConfig {
    case .appleSpeech:
      return NSLocalizedString("stt_provider.apple_speech", comment: "")
    case .whisperLocal:
      return NSLocalizedString("stt_provider.whisper_local", comment: "")
    case .openAICompatible:
      return NSLocalizedString("stt_provider.openai_compatible", comment: "")
    case .sonioxREST:
      return NSLocalizedString("stt_provider.soniox_rest", comment: "")
    }
  }

  private var requiresSpeechRecognition: Bool {
    if case .appleSpeech = providerConfig { return true }
    return false
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScrollView {
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

              Button {
                showProviderHelpPopover.toggle()
              } label: {
                Image(systemName: "info.circle")
                  .font(.footnote)
                  .foregroundStyle(.secondary)
                  .padding(4) // Larger hover/click target.
              }
              .buttonStyle(.plain)
              .help(Text("permissions_guide.current_provider_help"))
              .popover(isPresented: $showProviderHelpPopover, arrowEdge: .bottom) {
                Text("permissions_guide.current_provider_help")
                  .font(.footnote)
                  .padding(12)
                  .frame(width: 320, alignment: .leading)
              }
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
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      Divider()

      HStack {
        Button("permissions_guide.action.refresh") { permissions.refresh() }
        Spacer()
        Button("permissions_guide.action.done") { onDone() }
          .keyboardShortcut(.defaultAction)
      }
      .padding(20)
    }
    .frame(minWidth: 640, minHeight: 520)
    .onAppear {
      providerConfig = STTProviderStore.load()
      permissions.refresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: UserDefaults.standard)) { _ in
      providerConfig = STTProviderStore.load()
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
  @State private var showHelpPopover = false

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: kind.systemImageName)
        .foregroundStyle(.secondary)

      Text(kind.titleKey)
        .frame(width: 170, alignment: .leading)

      Text(status.localizedText(for: kind))
        .foregroundStyle(status.isSatisfied ? .green : .secondary)
        .frame(width: 140, alignment: .leading)

      Text(tag)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))

      Button {
        showHelpPopover.toggle()
      } label: {
        Image(systemName: "info.circle")
          .foregroundStyle(.secondary)
          .padding(4) // Larger hover/click target.
      }
      .buttonStyle(.plain)
      .help(Text(help))
      .popover(isPresented: $showHelpPopover, arrowEdge: .bottom) {
        Text(help)
          .font(.footnote)
          .padding(12)
          .frame(width: 320, alignment: .leading)
      }

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

  // Status text is shared with Settings' permission section via `PermissionStatus.localizedText`.
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
