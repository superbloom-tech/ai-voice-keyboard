import AppKit
import SwiftUI

struct SettingsLanguagePane: View {
  @AppStorage(AppLanguage.preferenceKey) private var appLanguageRawValue: String = AppLanguage.system.rawValue

  @State private var showRestartAlert = false

  private var languageBinding: Binding<AppLanguage> {
    Binding(
      get: { AppLanguage(rawValue: appLanguageRawValue) ?? .system },
      set: { newValue in
        let oldValue = AppLanguage(rawValue: appLanguageRawValue) ?? .system
        appLanguageRawValue = newValue.rawValue
        AppLanguage.applyToAppleLanguages(newValue)
        if newValue != oldValue {
          showRestartAlert = true
        }
      }
    )
  }

  var body: some View {
    Form {
      Section("settings.language.section_title") {
        Picker("settings.language.picker_label", selection: languageBinding) {
          Text("settings.language.option.system").tag(AppLanguage.system)
          Text("settings.language.option.en").tag(AppLanguage.en)
          Text("settings.language.option.zh_hans").tag(AppLanguage.zhHans)
          Text("settings.language.option.zh_hant").tag(AppLanguage.zhHant)
        }

        Text("settings.language.restart_hint")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .alert("settings.language.restart_title", isPresented: $showRestartAlert) {
      Button("settings.language.restart_action_later", role: .cancel) {}
      Button("settings.language.restart_action_quit") { NSApp.terminate(nil) }
    } message: {
      Text("settings.language.restart_message")
    }
  }
}

