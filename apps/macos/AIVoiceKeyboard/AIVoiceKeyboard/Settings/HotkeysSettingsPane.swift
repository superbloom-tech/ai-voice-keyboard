import AppKit
import SwiftUI

struct HotkeysSettingsPane: View {
  @ObservedObject var manager: HotKeyManager

  @State private var recordingAction: GlobalHotKeyCenter.Action?
  @State private var message: String?
  @State private var messageIsError: Bool = false

  var body: some View {
    SettingsCard(titleKey: "settings.section.hotkeys") {
      VStack(alignment: .leading, spacing: 12) {
        HotkeyRow(
          action: .toggleInsert,
          labelKey: "settings.hotkeys.insert_label",
          current: manager.configuration.insert,
          isRecording: binding(for: .toggleInsert),
          onCaptured: handleCapturedHotKey(_:for:)
        )

        HotkeyRow(
          action: .toggleEdit,
          labelKey: "settings.hotkeys.edit_label",
          current: manager.configuration.edit,
          isRecording: binding(for: .toggleEdit),
          onCaptured: handleCapturedHotKey(_:for:)
        )

        HStack(spacing: 10) {
          MonochromeButton("settings.hotkeys.action.reset_defaults") {
            applyResetToDefaults()
          }
          Spacer()
        }

        Text("settings.hotkeys.hint.modifier_requirement")
          .font(.footnote)
          .foregroundStyle(.secondary)

        if let message, !message.isEmpty {
          Text(message)
            .font(.footnote)
            .foregroundStyle(messageIsError ? .red : .secondary)
            .padding(.top, 2)
        }
      }
    }
  }

  private func binding(for action: GlobalHotKeyCenter.Action) -> Binding<Bool> {
    Binding(
      get: { recordingAction == action },
      set: { isOn in
        if isOn {
          recordingAction = action
          message = nil
          messageIsError = false
        } else if recordingAction == action {
          recordingAction = nil
        }
      }
    )
  }

  private func handleCapturedHotKey(_ hotKey: HotKey, for action: GlobalHotKeyCenter.Action) {
    // Update the correct side while keeping the other unchanged.
    var cfg = manager.configuration
    switch action {
    case .toggleInsert:
      cfg.insert = hotKey
    case .toggleEdit:
      cfg.edit = hotKey
    }

    do {
      try manager.apply(cfg)
      messageIsError = false
      message = NSLocalizedString("settings.hotkeys.status.applied", comment: "")
    } catch {
      messageIsError = true
      message = error.localizedDescription
    }

    recordingAction = nil
  }

  private func applyResetToDefaults() {
    do {
      try manager.resetToDefaults()
      messageIsError = false
      message = NSLocalizedString("settings.hotkeys.status.reset", comment: "")
    } catch {
      messageIsError = true
      message = error.localizedDescription
    }
  }
}

private struct HotkeyRow: View {
  let action: GlobalHotKeyCenter.Action
  let labelKey: LocalizedStringKey
  let current: HotKey
  @Binding var isRecording: Bool
  let onCaptured: (HotKey, GlobalHotKeyCenter.Action) -> Void

  @State private var captureHint: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        Text(labelKey)
          .frame(width: 120, alignment: .leading)

        Text(isRecording ? NSLocalizedString("settings.hotkeys.hint.press_keys", comment: "") : current.displayString)
          .font(.system(.body, design: .monospaced))
          .foregroundStyle(isRecording ? .secondary : Color(nsColor: .labelColor))
          .padding(.vertical, 6)
          .padding(.horizontal, 10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color(nsColor: .textBackgroundColor).opacity(isRecording ? 0.6 : 0.35))
          .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
          )
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        if isRecording {
          MonochromeButton("settings.hotkeys.action.cancel") {
            isRecording = false
          }
        } else {
          MonochromeButton("settings.hotkeys.action.change") {
            isRecording = true
          }
        }
      }

      if let captureHint, !captureHint.isEmpty {
        Text(captureHint)
          .font(.footnote)
          .foregroundStyle(.red)
      }

      // Invisible key capture view. When recording starts it becomes the first responder.
      HotKeyCaptureView(isRecording: $isRecording) { event in
        captureHint = nil

        if event.keyCode == 53 /* Esc */ {
          isRecording = false
          return
        }

        if event.modifierFlags.contains(.function) {
          captureHint = NSLocalizedString("settings.hotkeys.error.invalid.fn_not_supported", comment: "")
          return
        }

        let hk = HotKey(
          keyCode: UInt32(event.keyCode),
          modifiers: HotKey.modifiers(from: event.modifierFlags)
        )

        if let message = hk.validate() {
          captureHint = message
          return
        }

        onCaptured(hk, action)
      }
      .frame(width: 0, height: 0)
      .accessibilityHidden(true)
    }
  }
}

private struct HotKeyCaptureView: NSViewRepresentable {
  @Binding var isRecording: Bool
  let onKeyDown: (NSEvent) -> Void

  func makeNSView(context: Context) -> KeyCaptureNSView {
    let v = KeyCaptureNSView()
    v.onKeyDown = onKeyDown
    v.onResign = {
      // If focus moves away, exit recording to avoid "stuck recording" state.
      isRecording = false
    }
    return v
  }

  func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
    nsView.onKeyDown = onKeyDown

    if isRecording {
      DispatchQueue.main.async {
        nsView.window?.makeFirstResponder(nsView)
      }
    }
  }

  static func dismantleNSView(_ nsView: KeyCaptureNSView, coordinator: ()) {
    // Prevent state updates from `resignFirstResponder` after the SwiftUI view is torn down.
    nsView.onKeyDown = nil
    nsView.onResign = nil
  }
}

private final class KeyCaptureNSView: NSView {
  var onKeyDown: ((NSEvent) -> Void)?
  var onResign: (() -> Void)?

  override var acceptsFirstResponder: Bool { true }

  override func keyDown(with event: NSEvent) {
    onKeyDown?(event)
  }

  override func resignFirstResponder() -> Bool {
    let ok = super.resignFirstResponder()
    onResign?()
    return ok
  }
}
