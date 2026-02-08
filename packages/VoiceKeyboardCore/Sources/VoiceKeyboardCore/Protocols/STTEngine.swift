import Foundation

public struct STTTranscriptStream: Sendable {
  public let transcripts: AsyncThrowingStream<Transcript, Error>

  private let canceller: Canceller

  /// Create a transcript stream.
  ///
  /// This initializer binds `AsyncThrowingStream` termination to the provided cancellation handler.
  /// That means implementations get a reliable cleanup hook when consumers:
  /// - break out of iteration
  /// - cancel the consuming task
  /// - drop the stream/iterator
  ///
  /// - Important: `cancel` MUST be safe to call multiple times.
  public init(
    makeStream: @escaping @Sendable (AsyncThrowingStream<Transcript, Error>.Continuation) -> Void,
    cancel: @escaping @Sendable () async -> Void
  ) {
    let canceller = Canceller(cancel: cancel)
    self.canceller = canceller

    self.transcripts = AsyncThrowingStream { continuation in
      continuation.onTermination = { _ in
        Task {
          await canceller.cancel()
        }
      }

      makeStream(continuation)
    }
  }

  /// Explicitly cancel streaming and release underlying resources.
  ///
  /// This should cause the stream to stop yielding values and eventually finish.
  public func cancel() async {
    await canceller.cancel()
  }

  private actor Canceller {
    private var didCancel = false
    private let cancelImpl: @Sendable () async -> Void

    init(cancel: @escaping @Sendable () async -> Void) {
      self.cancelImpl = cancel
    }

    func cancel() async {
      guard !didCancel else { return }
      didCancel = true
      await cancelImpl()
    }
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
  /// - Implementations MUST release underlying audio/recognition resources when:
  ///   - the consumer cancels the Task iterating `transcripts`, OR
  ///   - the consumer stops iterating and the stream terminates (`AsyncThrowingStream` termination), OR
  ///   - `cancel()` is called.
  /// - Implementations MUST make cancellation safe and idempotent.
  ///
  /// Stream behavior expectations:
  /// - Implementations should yield partial updates frequently (`isFinal == false`).
  /// - Implementations should yield a final transcript (`isFinal == true`) before finishing *when
  ///   possible*.
  /// - On cancellation or errors, a final transcript may not be available.
  func streamTranscripts(locale: Locale) async throws -> STTTranscriptStream
}
