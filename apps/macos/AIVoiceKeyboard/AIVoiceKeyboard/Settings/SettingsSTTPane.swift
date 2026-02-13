import SwiftUI

struct SettingsSTTPane: View {
  @StateObject private var model = STTSettingsModel()

  var body: some View {
    STTSettingsSection(model: model)
  }
}

