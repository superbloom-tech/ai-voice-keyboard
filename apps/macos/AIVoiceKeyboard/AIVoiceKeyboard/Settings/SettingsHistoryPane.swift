import SwiftUI

struct SettingsHistoryPane: View {
  @AppStorage("avkb.persistHistoryEnabled") private var persistHistoryEnabled: Bool = false

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
    PreferencesPane {
      PreferencesGroupBox("settings.section.history") {
        Toggle("settings.history.persist_toggle", isOn: persistHistoryBinding)

        PreferencesFootnote("settings.history.persist_desc")
      }
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
