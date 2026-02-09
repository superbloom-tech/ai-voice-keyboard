import AVFoundation
import Foundation
import Speech

/// Minimal push-to-talk transcription using Apple Speech.
///
/// Lifecycle:
/// - `start()` begins streaming audio to the recognizer.
/// - `stop()` ends audio and returns the best final text (or best-effort partial).
final class AppleSpeechTranscriber {
  enum TranscriberError: LocalizedError {
    case recognizerUnavailable
    case alreadyRunning
    case notRunning
    case noAudioInput
    case noResult

    var errorDescription: String? {
      switch self {
      case .recognizerUnavailable:
        return "Speech recognizer unavailable"
      case .alreadyRunning:
        return "Transcriber already running"
      case .notRunning:
        return "Transcriber not running"
      case .noAudioInput:
        return "No audio input device"
      case .noResult:
        return "No transcription result"
      }
    }
  }

  private let audioEngine = AVAudioEngine()
  private let recognizer: SFSpeechRecognizer

  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?

  private var latestText: String = ""
  private var stopContinuation: CheckedContinuation<String, Error>?
  private var isStopping: Bool = false
  private var sawNonSilentAudio: Bool = false

  init(locale: Locale = .current) throws {
    guard let recognizer = SFSpeechRecognizer(locale: locale) else {
      throw TranscriberError.recognizerUnavailable
    }
    self.recognizer = recognizer
  }

  func start() throws {
    guard task == nil else { throw TranscriberError.alreadyRunning }
    guard recognizer.isAvailable else { throw TranscriberError.recognizerUnavailable }

    latestText = ""
    isStopping = false
    sawNonSilentAudio = false

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    self.request = request

    let input = audioEngine.inputNode
    let format = input.outputFormat(forBus: 0)
    if format.channelCount == 0 {
      throw TranscriberError.noAudioInput
    }

    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      guard let self else { return }
      guard !self.isStopping else { return }
      guard let request = self.request else { return }

      // Detect whether we ever received non-silent audio during this session.
      // If the mic is broken/muted, Apple Speech can fail with opaque errors; we prefer
      // a direct actionable message.
      if !self.sawNonSilentAudio {
        let audioBuf = buffer.audioBufferList.pointee.mBuffers
        if let mData = audioBuf.mData, audioBuf.mDataByteSize > 0 {
          let count = Int(audioBuf.mDataByteSize) / MemoryLayout<Int16>.size
          let samples = mData.bindMemory(to: Int16.self, capacity: count)
          for i in 0..<min(count, 512) {
            if samples[i] != 0 {
              self.sawNonSilentAudio = true
              break
            }
          }
        }
      }

      request.append(buffer)
    }

    audioEngine.prepare()
    try audioEngine.start()

    task = recognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self else { return }

      if let result {
        self.latestText = result.bestTranscription.formattedString
        if self.isStopping, result.isFinal {
          self.finishStop(.success(self.latestText))
          return
        }
      }

      if let error, self.isStopping {
        self.finishStop(.failure(error))
      }
    }
  }

  func stop(timeoutSeconds: Double = 2.0) async throws -> String {
    guard task != nil else { throw TranscriberError.notRunning }

    isStopping = true

    request?.endAudio()

    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)

    return try await withCheckedThrowingContinuation { continuation in
      stopContinuation = continuation

      DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
        guard let self else { return }
        guard self.stopContinuation != nil else { return }

        let trimmed = self.latestText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          self.finishStop(.success(self.latestText))
        } else {
          if !self.sawNonSilentAudio {
            self.finishStop(.failure(NSError(
              domain: "AIVoiceKeyboard",
              code: 1001,
              userInfo: [NSLocalizedDescriptionKey: "No audio captured. Check microphone input."]
            )))
          } else {
            self.finishStop(.failure(TranscriberError.noResult))
          }
        }
      }
    }
  }

  private func finishStop(_ result: Result<String, Error>) {
    guard let cont = stopContinuation else { return }
    stopContinuation = nil

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
