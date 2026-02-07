import SwiftUI

@main
struct AIVoiceKeyboardApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      SettingsView()
    }
  }
}

struct SettingsView: View {
  @StateObject private var permissions = PermissionCenter()

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("AI Voice Keyboard")
        .font(.title2)

      Text("Permissions")
        .font(.headline)

      PermissionRow(
        kind: .microphone,
        status: permissions.statuses[.microphone] ?? .unknown,
        onRequest: { await permissions.request(.microphone) },
        onOpenSystemSettings: { PermissionChecks.openSystemSettings(for: .microphone) }
      )

      PermissionRow(
        kind: .speechRecognition,
        status: permissions.statuses[.speechRecognition] ?? .unknown,
        onRequest: { await permissions.request(.speechRecognition) },
        onOpenSystemSettings: { PermissionChecks.openSystemSettings(for: .speechRecognition) }
      )

      PermissionRow(
        kind: .accessibility,
        status: permissions.statuses[.accessibility] ?? .unknown,
        onRequest: { await permissions.request(.accessibility) },
        onOpenSystemSettings: { PermissionChecks.openSystemSettings(for: .accessibility) }
      )

      Divider()

      HStack {
        Button("Refresh") {
          permissions.refresh()
        }
        Spacer()
      }

      Text("Tip: If a permission is denied, use “Open System Settings” to grant it, then click Refresh.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .padding(20)
    .frame(width: 520, height: 320)
    .onAppear {
      permissions.refresh()
    }
  }
}

private struct PermissionRow: View {
  let kind: PermissionKind
  let status: PermissionStatus

  let onRequest: () async -> Void
  let onOpenSystemSettings: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text(kind.displayName)
        .frame(width: 160, alignment: .leading)

      Text(status.displayText)
        .foregroundStyle(status.isSatisfied ? .green : .secondary)
        .frame(width: 140, alignment: .leading)

      Spacer()

      if status == .notDetermined {
        Button("Request") {
          Task { await onRequest() }
        }
      } else if status == .denied || status == .restricted {
        Button("Open System Settings") {
          onOpenSystemSettings()
        }
      } else if status == .authorized {
        Text("OK")
          .foregroundStyle(.secondary)
      } else {
        Button("Request") { Task { await onRequest() } }
      }
    }
  }
}
