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
    PreferencesPane {
      PreferencesGroupBox("settings.language.section_title") {
        Picker("settings.language.picker_label", selection: languageBinding) {
          Text("settings.language.option.system").tag(AppLanguage.system)
          Text("settings.language.option.en").tag(AppLanguage.en)
          Text("settings.language.option.zh_hans").tag(AppLanguage.zhHans)
          Text("settings.language.option.zh_hant").tag(AppLanguage.zhHant)
        }
        .pickerStyle(.menu)

        PreferencesFootnote("settings.language.restart_hint")
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
