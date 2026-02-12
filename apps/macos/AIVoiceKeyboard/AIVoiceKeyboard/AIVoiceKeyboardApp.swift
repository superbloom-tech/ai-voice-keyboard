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
