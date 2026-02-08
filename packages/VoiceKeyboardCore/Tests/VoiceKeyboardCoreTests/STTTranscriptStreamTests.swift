import XCTest
@testable import VoiceKeyboardCore

final class STTTranscriptStreamTests: XCTestCase {
  private actor Counter {
    private(set) var value = 0

    func increment() {
      value += 1
    }
  }

  private func waitUntil(_ condition: @escaping @Sendable () async -> Bool) async throws {
    let deadline = Date().addingTimeInterval(1.0)
    while Date() < deadline {
      if await condition() {
        return
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("timed out waiting for condition")
  }

  func testCancelIsIdempotent() async throws {
    let counter = Counter()

    let stream = STTTranscriptStream(
      makeStream: { continuation in
        continuation.yield(Transcript(text: "hi", isFinal: false))
      },
      cancel: {
        await counter.increment()
      }
    )

    await stream.cancel()
    await stream.cancel()

    let count = await counter.value
    XCTAssertEqual(count, 1)
  }

  func testTerminationTriggersCancel() async throws {
    let counter = Counter()

    var held: STTTranscriptStream? = STTTranscriptStream(
      makeStream: { continuation in
        continuation.yield(Transcript(text: "hi", isFinal: false))
      },
      cancel: {
        await counter.increment()
      }
    )

    XCTAssertNotNil(held)

    // Dropping the stream should eventually trigger termination and cancellation.
    held = nil

    try await waitUntil {
      await counter.value == 1
    }

    let count = await counter.value
    XCTAssertEqual(count, 1)
  }
}
