import SwiftUI

struct SettingsPermissionsPane: View {
  @StateObject private var permissions = PermissionCenter()

  var body: some View {
    PreferencesPane {
      PreferencesGroupBox {
        HStack(spacing: 10) {
          Button("permissions_guide.settings_button") {
            NotificationCenter.default.post(name: .avkbShowPermissionsGuide, object: nil)
          }

          Spacer()

          Button("permissions_guide.action.refresh") {
            permissions.refresh()
          }
        }
      }

      PreferencesGroupBox("permissions_guide.section.required") {
        SettingsPermissionRow(
          kind: .microphone,
          status: permissions.statuses[.microphone] ?? .unknown,
          onRequest: { await permissions.request(.microphone) },
          onOpenSystemSettings: { PermissionChecks.openSystemSettings(for: .microphone) },
          onRefresh: { permissions.refresh() }
        )

        Divider()

        SettingsPermissionRow(
          kind: .speechRecognition,
          status: permissions.statuses[.speechRecognition] ?? .unknown,
          onRequest: { await permissions.request(.speechRecognition) },
          onOpenSystemSettings: { PermissionChecks.openSystemSettings(for: .speechRecognition) },
          onRefresh: { permissions.refresh() }
        )

        PreferencesFootnote("settings.permissions.tip_denied")
      }

      PreferencesGroupBox("permissions_guide.section.auto_insert") {
        SettingsPermissionRow(
          kind: .accessibility,
          status: permissions.statuses[.accessibility] ?? .unknown,
          onRequest: { await permissions.request(.accessibility) },
          onOpenSystemSettings: { PermissionChecks.openSystemSettings(for: .accessibility) },
          onRefresh: { permissions.refresh() }
        )

        PreferencesFootnote("settings.permissions.tip_accessibility")
      }
    }
    .onAppear { permissions.refresh() }
  }
}

private struct SettingsPermissionRow: View {
  let kind: PermissionKind
  let status: PermissionStatus

  let onRequest: () async -> Void
  let onOpenSystemSettings: () -> Void
  let onRefresh: () -> Void

  private var iconName: String {
    switch kind {
    case .microphone:
      return "mic"
    case .speechRecognition:
      return "waveform"
    case .accessibility:
      return "hand.raised"
    }
  }

  var body: some View {
    LabeledContent {
      HStack(spacing: 10) {
        Text(status.localizedText(for: kind))
          .foregroundStyle(status.isSatisfied ? .secondary : .primary)

        Spacer()

        actions
      }
    } label: {
      Label(kind.displayName, systemImage: iconName)
    }
  }

  @ViewBuilder
  private var actions: some View {
    if kind == .accessibility {
      if status.isSatisfied {
        Text("permissions_guide.status.ok")
          .foregroundStyle(.secondary)
      } else {
        Button("permissions_guide.action.prompt") {
          Task { await onRequest() }
        }
        Button("permissions_guide.action.open_system_settings") {
          onOpenSystemSettings()
        }
        Button("permissions_guide.action.refresh") {
          onRefresh()
        }
      }
    } else {
      switch status {
      case .notDetermined:
        Button("permissions_guide.action.request") {
          Task { await onRequest() }
        }

      case .denied, .restricted:
        Button("permissions_guide.action.open_system_settings") {
          onOpenSystemSettings()
        }
        Button("permissions_guide.action.refresh") {
          onRefresh()
        }

      case .authorized:
        Text("permissions_guide.status.ok")
          .foregroundStyle(.secondary)

      case .unknown:
        Button("permissions_guide.action.refresh") {
          onRefresh()
        }
        Button("permissions_guide.action.open_system_settings") {
          onOpenSystemSettings()
        }
      }
    }
  }
}
