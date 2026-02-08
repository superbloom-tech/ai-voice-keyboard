import SwiftUI

extension Notification.Name {
  static let avkOpenSettingsRequest = Notification.Name("avk.openSettingsRequest")
  static let avkSettingsWindowClosed = Notification.Name("avk.settingsWindowClosed")
}

@main
struct AIVoiceKeyboardApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    // Hidden window provides a SwiftUI environment context for `openSettings`.
    // This is required for menu bar / accessory apps where calling Settings selectors is deprecated
    // and `openSettings()` can otherwise fail silently.
    Window("Hidden", id: "HiddenWindow") {
      if #available(macOS 14.0, *) {
        HiddenSettingsOpenerView14()
      } else {
        HiddenSettingsOpenerViewLegacy()
      }
    }
    .windowResizability(.contentSize)
    .defaultSize(width: 1, height: 1)

    Settings {
      SettingsView()
        .onDisappear {
          NotificationCenter.default.post(name: .avkSettingsWindowClosed, object: nil)
        }
    }
  }
}

@available(macOS 14.0, *)
private struct HiddenSettingsOpenerView14: View {
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Color.clear
      .frame(width: 1, height: 1)
      .onAppear {
#if DEBUG
        NSLog("[AIVoiceKeyboard] HiddenSettingsOpenerView14 onAppear")
#endif
      }
      .onReceive(NotificationCenter.default.publisher(for: .avkOpenSettingsRequest)) { _ in
        Task { @MainActor in
          // Make sure we temporarily behave like a regular app so Settings can appear frontmost.
          NSApp.setActivationPolicy(.regular)
          try? await Task.sleep(for: .milliseconds(120))

          NSApp.activate(ignoringOtherApps: true)
          openSettings()

          // Best-effort: bring the Settings window to the front once created.
          try? await Task.sleep(for: .milliseconds(220))
          if let settingsWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "com.apple.SwiftUI.Settings" }) {
            settingsWindow.makeKeyAndOrderFront(nil)
            settingsWindow.orderFrontRegardless()
          }
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .avkSettingsWindowClosed)) { _ in
        // Restore menu bar app state when Settings closes.
        NSApp.setActivationPolicy(.accessory)
      }
  }
}

private struct HiddenSettingsOpenerViewLegacy: View {
  var body: some View {
    Color.clear
      .frame(width: 1, height: 1)
      .onAppear {
#if DEBUG
        NSLog("[AIVoiceKeyboard] HiddenSettingsOpenerViewLegacy onAppear")
#endif
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
