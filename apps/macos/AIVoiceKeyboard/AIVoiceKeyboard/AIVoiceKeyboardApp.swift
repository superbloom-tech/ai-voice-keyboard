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

  @AppStorage(SettingsKeys.persistHistoryEnabled) private var persistHistoryEnabled: Bool = false

  @State private var showDisablePersistAlert = false

  private var persistHistoryBinding: Binding<Bool> {
    Binding(
      get: { persistHistoryEnabled },
      set: { newValue in
        if newValue {
          persistHistoryEnabled = true
        } else {
          // Confirm whether the on-disk file should be deleted when turning persistence off.
          showDisablePersistAlert = true
        }
      }
    )
  }

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
        onOpenSystemSettings: { PermissionChecks.openSystemSettings(for: .microphone) },
        onRefresh: { permissions.refresh() }
      )

      PermissionRow(
        kind: .speechRecognition,
        status: permissions.statuses[.speechRecognition] ?? .unknown,
        onRequest: { await permissions.request(.speechRecognition) },
        onOpenSystemSettings: { PermissionChecks.openSystemSettings(for: .speechRecognition) },
        onRefresh: { permissions.refresh() }
      )

      PermissionRow(
        kind: .accessibility,
        status: permissions.statuses[.accessibility] ?? .unknown,
        onRequest: { await permissions.request(.accessibility) },
        onOpenSystemSettings: { PermissionChecks.openSystemSettings(for: .accessibility) },
        onRefresh: { permissions.refresh() }
      )

      Divider()

      Text("History")
        .font(.headline)

      Toggle("Persist History to Disk", isOn: persistHistoryBinding)

      Text("Off (default): history stays in memory and is cleared on restart. On: history is saved to disk and persists across restarts.")
        .font(.footnote)
        .foregroundStyle(.secondary)

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

      Text("Accessibility is a trust setting (not a one-tap permission). After enabling it in System Settings, return to this app and click Refresh. Some apps may require refocus or relaunch to take effect.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .padding(20)
    .frame(width: 520, height: 400)
    .onAppear {
      permissions.refresh()
    }
    .alert("Turn Off Persistence?", isPresented: $showDisablePersistAlert) {
      Button("Cancel", role: .cancel) {}
      Button("Turn Off (Keep File)") {
        persistHistoryEnabled = false
      }
      Button("Turn Off (Delete File)", role: .destructive) {
        persistHistoryEnabled = false
        NotificationCenter.default.post(name: .avkbHistoryDeletePersistedFile, object: nil)
      }
    } message: {
      Text("Turning off persistence keeps history in memory for this session, but it will not be restored after restart. You can also delete the saved history file now.")
    }
  }
}

private struct PermissionRow: View {
  let kind: PermissionKind
  let status: PermissionStatus

  let onRequest: () async -> Void
  let onOpenSystemSettings: () -> Void
  let onRefresh: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text(kind.displayName)
        .frame(width: 160, alignment: .leading)

      Text(statusText)
        .foregroundStyle(status.isSatisfied ? .green : .secondary)
        .frame(width: 140, alignment: .leading)

      Spacer()

      if kind == .accessibility {
        // Accessibility isn't a normal permission flow: it's a trust setting that usually requires
        // manual enabling in System Settings and then returning to the app + refreshing.
        if status.isSatisfied {
          Text("OK")
            .foregroundStyle(.secondary)
        } else {
          Button("Prompt") { Task { await onRequest() } }
          Button("Open System Settings") { onOpenSystemSettings() }
        }
      } else {
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
          // For unknown/unsupported states, avoid calling request blindly.
          Button("Refresh") { onRefresh() }
          Button("Open System Settings") { onOpenSystemSettings() }
        }
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
