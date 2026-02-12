import AppKit
import SwiftUI

/// Root settings view shown by `SettingsWindowController`.
///
/// UI goal (Issue #64): grouped navigation at the top + a clean monochrome layout.
struct SettingsView: View {
  enum Pane: String, CaseIterable, Identifiable {
    case permissions
    case hotkeys
    case stt
    case postProcessing
    case history
    case language

    var id: String { rawValue }

    var segmentTitleKey: LocalizedStringKey {
      switch self {
      case .permissions: return "settings.nav.permissions"
      case .hotkeys: return "settings.nav.hotkeys"
      case .stt: return "settings.nav.stt"
      case .postProcessing: return "settings.nav.post_processing"
      case .history: return "settings.nav.history"
      case .language: return "settings.nav.language"
      }
    }
  }

  @StateObject private var permissions = PermissionCenter()
  @StateObject private var sttSettings = STTSettingsModel()
  @StateObject private var postProcessingSettings = PostProcessingSettingsModel()

  @ObservedObject var hotKeyManager: HotKeyManager

  @AppStorage("avkb.persistHistoryEnabled") private var persistHistoryEnabled: Bool = false
  @AppStorage(AppLanguage.preferenceKey) private var appLanguageRawValue: String = AppLanguage.system.rawValue

  @State private var selectedPane: Pane = .permissions
  @State private var showDisablePersistAlert = false
  @State private var showLanguageRestartAlert = false

  init(hotKeyManager: HotKeyManager) {
    self.hotKeyManager = hotKeyManager
  }

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
    VStack(spacing: 0) {
      headerBar
      Divider()
      content
      Divider()
      footerBar
    }
    .frame(width: 720, height: 760)
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear { permissions.refresh() }
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
    .alert("settings.language.restart_title", isPresented: $showLanguageRestartAlert) {
      Button("settings.language.restart_action_later", role: .cancel) {}
      Button("settings.language.restart_action_quit") { NSApp.terminate(nil) }
    } message: {
      Text("settings.language.restart_message")
    }
  }

  // MARK: - Chrome

  private var headerBar: some View {
    VStack(spacing: 10) {
      HStack {
        Text("settings.app_title")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(Color(nsColor: .labelColor))
        Spacer()
      }

      Picker("", selection: $selectedPane) {
        ForEach(Pane.allCases) { pane in
          Text(pane.segmentTitleKey).tag(pane)
        }
      }
      .pickerStyle(.segmented)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private var footerBar: some View {
    HStack {
      Text("settings.footer.prealpha_note")
        .font(.footnote)
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  // MARK: - Content

  private var content: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        switch selectedPane {
        case .permissions:
          permissionsPane
        case .hotkeys:
          HotkeysSettingsPane(manager: hotKeyManager)
        case .stt:
          SettingsCard(titleKey: "settings.section.stt") {
            STTSettingsSection(model: sttSettings)
          }
        case .postProcessing:
          SettingsCard(titleKey: "settings.section.post_processing") {
            PostProcessingSettingsSection(model: postProcessingSettings)
          }
        case .history:
          historyPane
        case .language:
          languagePane
        }
      }
      .padding(16)
    }
  }

  private var permissionsPane: some View {
    SettingsCard(titleKey: "settings.section.permissions") {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          MonochromeButton("permissions_guide.settings_button") {
            NotificationCenter.default.post(name: .avkbShowPermissionsGuide, object: nil)
          }
          Spacer()
          MonochromeButton("permissions_guide.action.refresh") {
            permissions.refresh()
          }
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

        VStack(alignment: .leading, spacing: 6) {
          Text("settings.permissions.tip_denied")
            .font(.footnote)
            .foregroundStyle(.secondary)

          Text("settings.permissions.tip_accessibility")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
      }
    }
  }

  private var historyPane: some View {
    SettingsCard(titleKey: "settings.section.history") {
      VStack(alignment: .leading, spacing: 10) {
        Toggle("settings.history.persist_toggle", isOn: persistHistoryBinding)
        Text("settings.history.persist_desc")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var languagePane: some View {
    SettingsCard(titleKey: "settings.language.section_title") {
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

      Text(status.localizedText(for: kind))
        .foregroundStyle(status.isSatisfied ? Color(nsColor: .labelColor) : .secondary)
        .frame(width: 140, alignment: .leading)

      Spacer()

      if kind == .accessibility {
        if status.isSatisfied {
          Text("permissions_guide.status.ok")
            .foregroundStyle(.secondary)
        } else {
          MonochromeButton("permissions_guide.action.prompt") { Task { await onRequest() } }
          MonochromeButton("permissions_guide.action.open_system_settings") { onOpenSystemSettings() }
        }
      } else {
        if status == .notDetermined {
          MonochromeButton("permissions_guide.action.request") { Task { await onRequest() } }
        } else if status == .denied || status == .restricted {
          MonochromeButton("permissions_guide.action.open_system_settings") { onOpenSystemSettings() }
        } else if status == .authorized {
          Text("permissions_guide.status.ok")
            .foregroundStyle(.secondary)
        } else {
          MonochromeButton("permissions_guide.action.refresh") { onRefresh() }
          MonochromeButton("permissions_guide.action.open_system_settings") { onOpenSystemSettings() }
        }
      }
    }
  }
}
