import AVFoundation
import Foundation
import Speech

/// Minimal Apple Speech transcriber for push-to-talk.
///
/// Design goals:
/// - Start/stop lifecycle controlled by the menu-bar app.
/// - Collect partial results while recording, but return the best final text on stop.
final class SpeechTranscriber {
  enum TranscriberError: LocalizedError {
    case recognizerUnavailable
    case noAudioInput
    case alreadyRecording
    case notRecording
    case timedOut

    var errorDescription: String? {
      switch self {
      case .recognizerUnavailable:
        return "Speech recognizer unavailable"
      case .noAudioInput:
        return "No audio input device"
      case .alreadyRecording:
        return "Already recording"
      case .notRecording:
        return "Not recording"
      case .timedOut:
        return "Transcription timed out"
      }
    }
  }

  private let audioEngine = AVAudioEngine()
  private let recognizer: SFSpeechRecognizer

  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?

  private var latestText: String = ""
  private var isStopping: Bool = false

  private var stopContinuation: CheckedContinuation<String, Error>?

  init(locale: Locale = .current) throws {
    guard let recognizer = SFSpeechRecognizer(locale: locale) else {
      throw TranscriberError.recognizerUnavailable
    }
    self.recognizer = recognizer
  }

  func start() throws {
    guard task == nil else { throw TranscriberError.alreadyRecording }
    guard recognizer.isAvailable else { throw TranscriberError.recognizerUnavailable }

    isStopping = false
    latestText = ""

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    self.request = request

    let inputNode = audioEngine.inputNode
    let format = inputNode.outputFormat(forBus: 0)

    if format.channelCount == 0 {
      throw TranscriberError.noAudioInput
    }

    inputNode.removeTap(onBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      self?.request?.append(buffer)
    }

    audioEngine.prepare()
    try audioEngine.start()

    task = recognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self else { return }

      if let result {
        self.latestText = result.bestTranscription.formattedString
        if self.isStopping, result.isFinal {
          self.finishStop(with: .success(self.latestText))
        }
      }

      if let error {
        // If we're stopping, treat an error as terminal; otherwise keep running.
        if self.isStopping {
          self.finishStop(with: .failure(error))
        }
      }
    }
  }

  func stop(timeoutSeconds: Double = 2.0) async throws -> String {
    guard task != nil else { throw TranscriberError.notRecording }

    isStopping = true

    request?.endAudio()
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)

    // Wait for the recognition task to deliver a final result.
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
      self.stopContinuation = continuation

      // Timeout: if we never get a final, return the latest partial as best-effort.
      DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
        guard let self else { return }
        guard self.stopContinuation != nil else { return }

        if !self.latestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          self.finishStop(with: .success(self.latestText))
        } else {
          self.finishStop(with: .failure(TranscriberError.timedOut))
        }
      }
    }
  }

  private func finishStop(with result: Result<String, Error>) {
    guard let cont = stopContinuation else { return }
    stopContinuation = nil

    // Clean up task/request so the next recording can start cleanly.
    task?.cancel()
    task = nil
    request = nil

    isStopping = false

    switch result {
    case .success(let text):
      cont.resume(returning: text)
    case .failure(let error):
      cont.resume(throwing: error)
    }
  }
}
