import Foundation
import VoiceKeyboardCore

actor PushToTalkSTTSession {
  enum SessionError: LocalizedError {
    case alreadyRunning
    case notRunning
    case noResult

    var errorDescription: String? {
      switch self {
      case .alreadyRunning:
        return "STT session already running"
      case .notRunning:
        return "STT session not running"
      case .noResult:
        return "No transcription result"
      }
    }
  }

  private var stream: STTTranscriptStream?
  private var consumerTask: Task<Void, Never>?

  private var latestText: String = ""
  private var finalText: String?
  private var completionError: Error?

  private var generation: Int = 0
  private var activeGeneration: Int?

  func start(engine: any STTEngine, locale: Locale) async throws {
    guard stream == nil else { throw SessionError.alreadyRunning }

    generation += 1
    let gen = generation
    activeGeneration = gen

    latestText = ""
    finalText = nil
    completionError = nil

    NSLog("[STTSession] Starting session (generation: %d, engine: %@, locale: %@)",
          gen, engine.id, locale.identifier)

    let stream = try await engine.streamTranscripts(locale: locale)
    self.stream = stream

    consumerTask = Task { [stream] in
      do {
        for try await transcript in stream.transcripts {
          await self.handleTranscript(transcript, generation: gen)
        }
        await self.handleCompletion(error: nil, generation: gen)
      } catch {
        await self.handleCompletion(error: error, generation: gen)
      }
    }
    NSLog("[STTSession] Consumer task started")
  }

  func stop(timeoutSeconds: Double) async throws -> String {
    guard let stream else { throw SessionError.notRunning }

    NSLog("[STTSession] Stopping session (timeout: %.1fs)", timeoutSeconds)

    let task = consumerTask
    await stream.cancel()

    if let task {
      let finished = await waitForTask(task, timeoutSeconds: timeoutSeconds)
      if !finished {
        NSLog("[STTSession] WARNING: Consumer task did not finish within timeout, cancelling")
        task.cancel()
      } else {
        NSLog("[STTSession] Consumer task finished normally")
      }
    }

    let err = completionError
    let text = finalText ?? latestText
    NSLog("[STTSession] Result — finalText: %@, latestText: \"%@\", error: %@",
          finalText != nil ? "\"\(finalText!)\"" : "nil",
          latestText,
          err?.localizedDescription ?? "nil")

    // Reset for next run.
    self.stream = nil
    self.consumerTask = nil
    self.latestText = ""
    self.finalText = nil
    self.completionError = nil
    self.activeGeneration = nil

    if let err { throw err }

    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      NSLog("[STTSession] ERROR: No result (text empty after trimming)")
      throw SessionError.noResult
    }
    NSLog("[STTSession] Returning text: \"%@\" (length: %d)", text, text.count)
    return text
  }

  private func handleTranscript(_ transcript: Transcript, generation: Int) {
    guard activeGeneration == generation else {
      NSLog("[STTSession] Ignoring transcript from stale generation %d (active: %d)", generation, activeGeneration ?? -1)
      return
    }
    NSLog("[STTSession] Received transcript (isFinal: %d): \"%@\"", transcript.isFinal ? 1 : 0, transcript.text)
    latestText = transcript.text
    if transcript.isFinal {
      finalText = transcript.text
    }
  }

  private func handleCompletion(error: Error?, generation: Int) {
    guard activeGeneration == generation else { return }
    if let error {
      NSLog("[STTSession] Stream completed with error: %@", error.localizedDescription)
    } else {
      NSLog("[STTSession] Stream completed normally")
    }
    completionError = error
  }

  private func waitForTask(_ task: Task<Void, Never>, timeoutSeconds: Double) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        await task.value
        return true
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
        return false
      }

      let result = await group.next() ?? false
      group.cancelAll()
      return result
    }
  }
}

