import Foundation

public struct STTTranscriptStream: Sendable {
  public let transcripts: AsyncThrowingStream<Transcript, Error>

  private let cancelImpl: @Sendable () async -> Void

  public init(
    transcripts: AsyncThrowingStream<Transcript, Error>,
    cancel: @escaping @Sendable () async -> Void
  ) {
    self.transcripts = transcripts
    self.cancelImpl = cancel
  }

  public func cancel() async {
    await cancelImpl()
  }
}

public protocol STTEngine: Sendable {
  var id: String { get }
  var displayName: String { get }

  func capabilities() async -> STTCapabilities

  /// Stream transcription updates.
  ///
  /// - Returns: A stream of `Transcript` values and an explicit cancellation handle.
  ///
  /// Cancellation + lifecycle contract:
  /// - Implementations MUST release underlying audio/recognition resources when either:
  ///   - the consumer cancels the Task iterating `transcripts`, OR
  ///   - the consumer stops iterating and the stream terminates (`AsyncThrowingStream` termination), OR
  ///   - `cancel()` is called.
  /// - The stream should yield partial updates frequently (`isFinal == false`) and eventually yield a
  ///   final transcript (`isFinal == true`) before finishing normally.
  func streamTranscripts(locale: Locale) async throws -> STTTranscriptStream
}
