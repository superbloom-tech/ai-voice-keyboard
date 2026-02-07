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
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("AI Voice Keyboard")
        .font(.title2)
      Text("Menu bar app skeleton. Hotkeys/HUD/permissions will be implemented in follow-up issues.")
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(20)
    .frame(width: 420, height: 160)
  }
}

