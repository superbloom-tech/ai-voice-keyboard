import SwiftUI

struct SettingsPostProcessingPane: View {
  @StateObject private var model = PostProcessingSettingsModel()

  var body: some View {
    PostProcessingSettingsSection(model: model)
  }
}

