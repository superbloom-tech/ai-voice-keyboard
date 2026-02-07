import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import Speech

enum PermissionKind: String, CaseIterable, Sendable {
  case microphone
  case speechRecognition
  case accessibility

  var displayName: String {
    switch self {
    case .microphone:
      return "Microphone"
    case .speechRecognition:
      return "Speech Recognition"
    case .accessibility:
      return "Accessibility"
    }
  }
}

enum PermissionStatus: String, Sendable {
  case authorized
  case denied
  case notDetermined
  case restricted
  case unknown

  var isSatisfied: Bool { self == .authorized }

  var displayText: String {
    switch self {
    case .authorized:
      return "Authorized"
    case .denied:
      return "Denied"
    case .notDetermined:
      return "Not Determined"
    case .restricted:
      return "Restricted"
    case .unknown:
      return "Unknown"
    }
  }
}

enum PermissionChecks {
  static func status(for kind: PermissionKind) -> PermissionStatus {
    switch kind {
    case .microphone:
      switch AVCaptureDevice.authorizationStatus(for: .audio) {
      case .authorized:
        return .authorized
      case .denied:
        return .denied
      case .notDetermined:
        return .notDetermined
      case .restricted:
        return .restricted
      @unknown default:
        return .unknown
      }

    case .speechRecognition:
      switch SFSpeechRecognizer.authorizationStatus() {
      case .authorized:
        return .authorized
      case .denied:
        return .denied
      case .notDetermined:
        return .notDetermined
      case .restricted:
        return .restricted
      @unknown default:
        return .unknown
      }

    case .accessibility:
      // Accessibility is a trust setting (AXIsProcessTrusted), not a standard "notDetermined/denied" flow.
      return AXIsProcessTrusted() ? .authorized : .denied
    }
  }

  static func request(_ kind: PermissionKind) async -> PermissionStatus {
    switch kind {
    case .microphone:
      return await requestMicrophone()
    case .speechRecognition:
      return await requestSpeechRecognition()
    case .accessibility:
      // Shows the system prompt. The user must still manually enable the app in System Settings.
      // The trusted state often only flips after returning to the app and re-checking (Refresh).
      let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
      _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
      return status(for: .accessibility)
    }
  }

  static func openSystemSettings(for kind: PermissionKind) {
    // `x-apple.systempreferences:` deep links are not a stable public API; keep this logic centralized.
    let urlString: String
    switch kind {
    case .microphone:
      urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    case .speechRecognition:
      urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
    case .accessibility:
      urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    }

    if let url = URL(string: urlString) {
      NSWorkspace.shared.open(url)
    } else {
      // Fallback: open System Settings root.
      NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/System Settings.app"), configuration: .init())
    }
  }

  private static func requestMicrophone() async -> PermissionStatus {
    await withCheckedContinuation { continuation in
      AVCaptureDevice.requestAccess(for: .audio) { _ in
        continuation.resume(returning: status(for: .microphone))
      }
    }
  }

  private static func requestSpeechRecognition() async -> PermissionStatus {
    await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { _ in
        continuation.resume(returning: status(for: .speechRecognition))
      }
    }
  }
}

@MainActor
final class PermissionCenter: ObservableObject {
  @Published private(set) var statuses: [PermissionKind: PermissionStatus] = [:]

  init() {
    refresh()
  }

  func refresh() {
    var next: [PermissionKind: PermissionStatus] = [:]
    for kind in PermissionKind.allCases {
      next[kind] = PermissionChecks.status(for: kind)
    }
    statuses = next
  }

  func request(_ kind: PermissionKind) async {
    _ = await PermissionChecks.request(kind)
    refresh()
  }
}
