import Foundation

public protocol STTEngine: Sendable {
  var id: String { get }
  var displayName: String { get }

  func capabilities() async -> STTCapabilities

  /// Begin streaming transcription. Implementations should invoke `onPartial` frequently with partial updates.
  func startStreaming(
    locale: Locale,
    onPartial: @escaping @Sendable (Transcript) -> Void
  ) async throws

  /// Stop streaming transcription and return a final transcript.
  func stopStreaming() async throws -> Transcript
}

