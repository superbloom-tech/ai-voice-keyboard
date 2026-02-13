import AppKit
import SwiftUI

/// Native macOS "Preferences" window shell using toolbar-style tabs.
///
/// This intentionally lives in AppKit to get the same look/feel as System Settings:
/// icon+label toolbar items at the top, with each pane rendered by SwiftUI.
@MainActor
final class PreferencesTabViewController: NSTabViewController {
  private let hotKeyManager: HotKeyManager

  init(hotKeyManager: HotKeyManager) {
    self.hotKeyManager = hotKeyManager
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    tabStyle = .toolbar

    // NOTE(macOS 15.7): Setting `tabViewItems = [...]` crashes due to an AppKit bug
    // (`NSTabViewControllerToolbarUIProvider` missing selector). Incremental adds work.
    let items: [NSTabViewItem] = [
      makeTabItem(rootView: SettingsPermissionsPane(), titleKey: "settings.nav.permissions", systemImageName: "lock"),
      makeTabItem(rootView: HotkeysSettingsPane(manager: hotKeyManager), titleKey: "settings.nav.hotkeys", systemImageName: "keyboard"),
      makeTabItem(rootView: SettingsSTTPane(), titleKey: "settings.nav.stt", systemImageName: "waveform"),
      makeTabItem(rootView: SettingsPostProcessingPane(), titleKey: "settings.nav.post_processing", systemImageName: "sparkles"),
      makeTabItem(rootView: SettingsHistoryPane(), titleKey: "settings.nav.history", systemImageName: "clock.arrow.circlepath"),
      makeTabItem(rootView: SettingsLanguagePane(), titleKey: "settings.nav.language", systemImageName: "globe"),
    ]
    for item in items {
      addTabViewItem(item)
    }
    selectedTabViewItemIndex = 0
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    updateWindowTitleFromSelectedTab()
  }

  override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
    super.tabView(tabView, didSelect: tabViewItem)
    updateWindowTitleFromSelectedTab()
  }

  private func makeTabItem<Content: View>(
    rootView: Content,
    titleKey: String,
    systemImageName: String
  ) -> NSTabViewItem {
    let title = NSLocalizedString(titleKey, comment: "")
    let viewController = NSHostingController(rootView: rootView)
    viewController.title = title

    let item = NSTabViewItem(viewController: viewController)
    item.label = title
    item.image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: nil)
    return item
  }

  private func updateWindowTitleFromSelectedTab() {
    guard selectedTabViewItemIndex >= 0, selectedTabViewItemIndex < tabViewItems.count else { return }
    let label = tabViewItems[selectedTabViewItemIndex].label
    guard !label.isEmpty else { return }
    view.window?.title = label
  }
}
