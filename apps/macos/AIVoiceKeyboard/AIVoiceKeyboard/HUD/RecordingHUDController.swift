import AppKit
import SwiftUI

/// Non-interactive always-on-top HUD shown while recording.
@MainActor
final class RecordingHUDController {
  final class Model: ObservableObject {
    @Published var modeLabel: String = "Insert"
    @Published var startedAt: Date = Date()
    @Published var partialTranscript: String = ""
    @Published var isRecording: Bool = false
  }

  private let model = Model()
  private let panel: RecordingHUDPanel

  init() {
    let size = NSSize(width: 420, height: 96)
    let rect = NSRect(origin: .zero, size: size)

    let panel = RecordingHUDPanel(
      contentRect: rect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    self.panel = panel

    panel.isReleasedWhenClosed = false
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.ignoresMouseEvents = true // click-through
    panel.hidesOnDeactivate = false

    let view = RecordingHUDView(model: model)
      .padding(16)

    panel.contentViewController = NSHostingController(rootView: view)

    updatePosition()
  }

  func update(for status: AppState.Status) {
    switch status {
    case .recordingInsert:
      showIfNeeded(modeLabel: "Insert")
    case .recordingEdit:
      showIfNeeded(modeLabel: "Edit")
    default:
      hideIfNeeded()
    }
  }

  private func showIfNeeded(modeLabel: String) {
    let wasRecording = model.isRecording
    model.modeLabel = modeLabel

    if !wasRecording {
      model.startedAt = Date()
      model.partialTranscript = ""
    }

    model.isRecording = true

    updatePosition()
    panel.orderFrontRegardless()
  }

  private func hideIfNeeded() {
    guard model.isRecording else { return }
    model.isRecording = false
    panel.orderOut(nil)
  }

  private func updatePosition() {
    let screen = NSScreen.main ?? NSScreen.screens.first
    guard let visibleFrame = screen?.visibleFrame else { return }

    let frame = panel.frame
    // `visibleFrame.maxY` is already below the menu bar. If we want the HUD to visually "attach"
    // to the menu bar, we can allow it to overlap upward by a few points.
    let menuBarOverlap: CGFloat = 4
    let gapBelowMenuBar: CGFloat = 0
    let xOffset: CGFloat = -24

    // Top-center of visible screen.
    let x = visibleFrame.midX - (frame.width / 2) + xOffset
    let y = visibleFrame.maxY - frame.height + menuBarOverlap - gapBelowMenuBar

    panel.setFrameOrigin(NSPoint(x: x, y: y))
  }
}

private final class RecordingHUDPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

private struct RecordingHUDView: View {
  @ObservedObject var model: RecordingHUDController.Model

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Text(model.modeLabel.uppercased())
          .font(.caption.weight(.semibold))
          .padding(.vertical, 4)
          .padding(.horizontal, 8)
          .background(Capsule().fill(Color.accentColor.opacity(0.18)))

        TimelineView(.periodic(from: model.startedAt, by: 1.0)) { context in
          Text(elapsedText(now: context.date, startedAt: model.startedAt))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        Spacer()

        Image(systemName: "waveform")
          .foregroundStyle(.secondary)
      }

      if model.partialTranscript.isEmpty {
        Text("Listening...")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        Text(model.partialTranscript)
          .font(.caption)
          .lineLimit(2)
      }
    }
    .padding(12)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.08))
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func elapsedText(now: Date, startedAt: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(startedAt)))
    let minutes = seconds / 60
    let remainder = seconds % 60
    return String(format: "%02d:%02d", minutes, remainder)
  }
}
