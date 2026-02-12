import AppKit
import SwiftUI

/// Minimal monochrome button: outlined by default, and inverts foreground/background on hover.
struct MonochromeButton: View {
  private let title: LocalizedStringKey
  private let action: () -> Void
  @State private var isHovering = false

  init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
    self.title = title
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 12, weight: .medium))
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .foregroundStyle(isHovering ? Color(nsColor: .windowBackgroundColor) : Color(nsColor: .labelColor))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(isHovering ? Color(nsColor: .labelColor) : Color.clear)
    .overlay(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .stroke(Color(nsColor: .labelColor).opacity(0.35), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .onHover { isHovering = $0 }
  }
}

struct SettingsCard<Content: View>: View {
  let titleKey: LocalizedStringKey
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(titleKey)
        .font(.headline)
        .foregroundStyle(Color(nsColor: .labelColor))

      content()
    }
    .padding(16)
    .background(Color(nsColor: .controlBackgroundColor))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}
