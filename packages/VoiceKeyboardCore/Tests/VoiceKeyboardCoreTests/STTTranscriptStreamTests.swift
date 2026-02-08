import XCTest
@testable import VoiceKeyboardCore

final class STTTranscriptStreamTests: XCTestCase {
  func testCancelIsIdempotent() async throws {
    let lock = NSLock()
    var cancelCount = 0

    let stream = STTTranscriptStream(
      makeStream: { continuation in
        continuation.yield(Transcript(text: "hi", isFinal: false))
      },
      cancel: {
        lock.lock()
        cancelCount += 1
        lock.unlock()
      }
    )

    await stream.cancel()
    await stream.cancel()

    lock.lock()
    let count = cancelCount
    lock.unlock()

    XCTAssertEqual(count, 1)
  }

  func testTerminationTriggersCancel() async throws {
    let lock = NSLock()
    var cancelCount = 0

    var held: STTTranscriptStream? = STTTranscriptStream(
      makeStream: { continuation in
        continuation.yield(Transcript(text: "hi", isFinal: false))
      },
      cancel: {
        lock.lock()
        cancelCount += 1
        lock.unlock()
      }
    )

    // Dropping the stream should eventually trigger termination and cancellation.
    held = nil

    // Give the Task spawned from onTermination a moment to run.
    try await Task.sleep(nanoseconds: 50_000_000)

    lock.lock()
    let count = cancelCount
    lock.unlock()

    XCTAssertEqual(count, 1)
  }
}
