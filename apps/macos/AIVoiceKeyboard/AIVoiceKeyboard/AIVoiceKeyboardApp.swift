import AppKit
import SwiftUI

@main
struct AIVoiceKeyboardApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  init() {
    // Unit tests run with a host app. Avoid mutating language defaults during tests.
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
      AppLanguage.applySavedPreference()
    }
  }

  var body: some Scene {
    // This is a menu bar app (LSUIElement + `.accessory` activation policy). We intentionally
    // do not create a main WindowGroup, otherwise macOS will show an empty window at launch.
    //
    // Settings are presented via `SettingsWindowController` in AppDelegate.
    Settings {
      EmptyView()
    }
  }
}

struct SettingsView: View {
  @StateObject private var permissions = PermissionCenter()
  @StateObject private var sttSettings = STTSettingsModel()
  @StateObject private var postProcessingSettings = PostProcessingSettingsModel()

  @AppStorage("avkb.persistHistoryEnabled") private var persistHistoryEnabled: Bool = false
  @AppStorage(AppLanguage.preferenceKey) private var appLanguageRawValue: String = AppLanguage.system.rawValue

  @State private var showDisablePersistAlert = false
  @State private var showLanguageRestartAlert = false

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

  private var languageBinding: Binding<AppLanguage> {
    Binding(
      get: { AppLanguage(rawValue: appLanguageRawValue) ?? .system },
      set: { newValue in
        let oldValue = AppLanguage(rawValue: appLanguageRawValue) ?? .system
        appLanguageRawValue = newValue.rawValue
        AppLanguage.applyToAppleLanguages(newValue)
        if newValue != oldValue {
          showLanguageRestartAlert = true
        }
      }
    )
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("settings.app_title")
          .font(.title2)

        GroupBox("settings.language.section_title") {
          VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
              Text("settings.language.picker_label")
                .frame(width: 160, alignment: .leading)

              Picker("", selection: languageBinding) {
                Text("settings.language.option.system").tag(AppLanguage.system)
                Text("settings.language.option.en").tag(AppLanguage.en)
                Text("settings.language.option.zh_hans").tag(AppLanguage.zhHans)
                Text("settings.language.option.zh_hant").tag(AppLanguage.zhHant)
              }
              .labelsHidden()

              Spacer()
            }

            Text("settings.language.restart_hint")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          .padding(.top, 6)
        }
        .alert("settings.language.restart_title", isPresented: $showLanguageRestartAlert) {
          Button("settings.language.restart_action_later", role: .cancel) {}
          Button("settings.language.restart_action_quit") {
            NSApp.terminate(nil)
          }
        } message: {
          Text("settings.language.restart_message")
        }

        GroupBox("settings.section.permissions") {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Button("permissions_guide.settings_button") {
                NotificationCenter.default.post(name: .avkbShowPermissionsGuide, object: nil)
              }
              Spacer()
            }

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

            HStack {
              Button("permissions_guide.action.refresh") {
                permissions.refresh()
              }
              Spacer()
            }

            Text("settings.permissions.tip_denied")
              .font(.footnote)
              .foregroundStyle(.secondary)

            Text("settings.permissions.tip_accessibility")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          .padding(.top, 6)
        }

        GroupBox("settings.section.history") {
          VStack(alignment: .leading, spacing: 8) {
            Toggle("settings.history.persist_toggle", isOn: persistHistoryBinding)

            Text("settings.history.persist_desc")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          .padding(.top, 6)
        }

        GroupBox("settings.section.stt") {
          STTSettingsSection(model: sttSettings)
            .padding(.top, 6)
        }

        GroupBox("settings.section.post_processing") {
          PostProcessingSettingsSection(model: postProcessingSettings)
            .padding(.top, 6)
        }
      }
      .padding(20)
    }
    .frame(width: 560, height: 780)
    .onAppear {
      permissions.refresh()
    }
    .alert("settings.history.alert_disable_title", isPresented: $showDisablePersistAlert) {
      Button("common.action.cancel", role: .cancel) {}
      Button("settings.history.alert_action_turn_off_keep") {
        persistHistoryEnabled = false
      }
      Button("settings.history.alert_action_turn_off_delete", role: .destructive) {
        persistHistoryEnabled = false
        NotificationCenter.default.post(name: .avkbHistoryDeletePersistedFile, object: nil)
      }
    } message: {
      Text("settings.history.alert_disable_message")
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
          Text("permissions_guide.status.ok")
            .foregroundStyle(.secondary)
        } else {
          Button("permissions_guide.action.prompt") { Task { await onRequest() } }
          Button("permissions_guide.action.open_system_settings") { onOpenSystemSettings() }
        }
      } else {
        if status == .notDetermined {
          Button("permissions_guide.action.request") {
            Task { await onRequest() }
          }
        } else if status == .denied || status == .restricted {
          Button("permissions_guide.action.open_system_settings") {
            onOpenSystemSettings()
          }
        } else if status == .authorized {
          Text("permissions_guide.status.ok")
            .foregroundStyle(.secondary)
        } else {
          // For unknown/unsupported states, avoid calling request blindly.
          Button("permissions_guide.action.refresh") { onRefresh() }
          Button("permissions_guide.action.open_system_settings") { onOpenSystemSettings() }
        }
      }
    }
  }

  private var statusText: String {
    if kind == .accessibility {
      return status.isSatisfied
        ? NSLocalizedString("permission.status.trusted", comment: "")
        : NSLocalizedString("permission.status.not_trusted", comment: "")
    }
    return status.displayText
  }
}

// MARK: - Language override

private enum AppLanguage: String, CaseIterable, Identifiable {
  case system = "system"
  case en = "en"
  case zhHans = "zh-Hans"
  case zhHant = "zh-Hant"

  static let preferenceKey = "avkb.language.preference"
  private static let systemAppleLanguagesBackupKey = "avkb.language.systemAppleLanguagesBackup"

  var id: String { rawValue }

  private var appleLanguageCode: String? {
    self == .system ? nil : rawValue
  }

  static func load() -> AppLanguage {
    let raw = UserDefaults.standard.string(forKey: preferenceKey) ?? AppLanguage.system.rawValue
    return AppLanguage(rawValue: raw) ?? .system
  }

  static func applySavedPreference() {
    applyToAppleLanguages(load())
  }

  static func applyToAppleLanguages(_ language: AppLanguage) {
    // `AppleLanguages` affects `Bundle.main.preferredLocalizations`.
    let defaults = UserDefaults.standard
    let appleLanguagesKey = "AppleLanguages"

    if let code = language.appleLanguageCode {
      // Preserve the "system-determined" app language (including per-app language override in
      // macOS System Settings) so selecting `.system` can restore it.
      if defaults.object(forKey: systemAppleLanguagesBackupKey) == nil {
        let existing = defaults.stringArray(forKey: appleLanguagesKey) ?? []
        defaults.set(existing, forKey: systemAppleLanguagesBackupKey)
      }
      defaults.set([code], forKey: appleLanguagesKey)
      return
    }

    // `.system`: restore previous AppleLanguages value only if we ever overrode it.
    guard let backup = defaults.array(forKey: systemAppleLanguagesBackupKey) as? [String] else {
      return
    }
    defer { defaults.removeObject(forKey: systemAppleLanguagesBackupKey) }

    if backup.isEmpty {
      defaults.removeObject(forKey: appleLanguagesKey)
    } else {
      defaults.set(backup, forKey: appleLanguagesKey)
    }
  }
}
