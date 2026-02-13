import SwiftUI

/// Shared "native preferences" building blocks for Settings panes.
///
/// Goal: keep each pane focused on *what* to show (groups + rows), not on layout boilerplate.
struct PreferencesPane<Content: View>: View {
  @ViewBuilder let content: () -> Content

  init(@ViewBuilder content: @escaping () -> Content) {
    self.content = content
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        content()
      }
      // Keep a comfortable reading width even when the window is wide.
      .frame(maxWidth: 720, alignment: .leading)
      .padding(20)
      // Center the fixed-width column within the window.
      .frame(maxWidth: .infinity, alignment: .center)
    }
  }
}

struct PreferencesGroupBox<Content: View>: View {
  private let titleKey: LocalizedStringKey?
  @ViewBuilder private let content: () -> Content

  init(_ titleKey: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
    self.titleKey = titleKey
    self.content = content
  }

  init(@ViewBuilder content: @escaping () -> Content) {
    self.titleKey = nil
    self.content = content
  }

  var body: some View {
    if let titleKey {
      GroupBox {
        groupContent
      } label: {
        Text(titleKey)
          .font(.headline)
      }
    } else {
      GroupBox {
        groupContent
      }
    }
  }

  private var groupContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct PreferencesFootnote: View {
  private let key: LocalizedStringKey

  init(_ key: LocalizedStringKey) {
    self.key = key
  }

  var body: some View {
    Text(key)
      .font(.footnote)
      .foregroundStyle(.secondary)
  }
}

