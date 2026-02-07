import Foundation

public protocol STTEngine: Sendable {
  var id: String { get }
  var displayName: String { get }

  func capabilities() async -> STTCapabilities

  /// Begin streaming transcription.
  ///
  /// - Important: Callers must ensure `stopStreaming()` is eventually called (typically in a `defer`)
  ///   to allow implementations to release audio / recognition resources. Cancellation does not
  ///   implicitly stop the engine.
  ///
  /// Implementations should invoke `onPartial` frequently with partial updates.
  func startStreaming(
    locale: Locale,
    onPartial: @escaping @Sendable (Transcript) -> Void
  ) async throws

  /// Stop streaming transcription and return a final transcript.
  func stopStreaming() async throws -> Transcript
}
