import AVFoundation
import Foundation
import Speech
import VoiceKeyboardCore

actor AppleSpeechSTTEngine: STTEngine {
  enum EngineError: LocalizedError {
    case recognizerUnavailable
    case alreadyRunning
    case noAudioInput
    case noResult

    var errorDescription: String? {
      switch self {
      case .recognizerUnavailable:
        return "Speech recognizer unavailable"
      case .alreadyRunning:
        return "Speech recognizer already running"
      case .noAudioInput:
        return "No audio input device"
      case .noResult:
        return "No transcription result"
      }
    }
  }

  nonisolated let id: String = "apple_speech"
  nonisolated let displayName: String = "Apple Speech"

  private let configuration: AppleSpeechConfiguration

  private var audioEngine: AVAudioEngine?
  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?

  private var continuation: AsyncThrowingStream<Transcript, Error>.Continuation?

  private var latestText: String = ""
  private var didYieldFinal: Bool = false
  private var isStopping: Bool = false
  private var didFinish: Bool = false
  private var sawNonSilentAudio: Bool = false

  private var stopTimer: DispatchSourceTimer?

  init(configuration: AppleSpeechConfiguration = AppleSpeechConfiguration()) {
    self.configuration = configuration
  }

  func capabilities() async -> STTCapabilities {
    STTCapabilities(
      supportsStreaming: true,
      supportsOnDeviceRecognition: nil,
      supportedLocaleIdentifiers: nil
    )
  }

  func streamTranscripts(locale: Locale) async throws -> STTTranscriptStream {
    guard continuation == nil, !didFinish else { throw EngineError.alreadyRunning }

    let effectiveLocale: Locale = {
      guard let raw = configuration.localeIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty else {
        return locale
      }
      return Locale(identifier: raw)
    }()

    guard let recognizer = SFSpeechRecognizer(locale: effectiveLocale), recognizer.isAvailable else {
      throw EngineError.recognizerUnavailable
    }

    return STTTranscriptStream(
      makeStream: { continuation in
        Task { await self.start(recognizer: recognizer, continuation: continuation) }
      },
      cancel: {
        await self.stop()
      }
    )
  }

  private func start(
    recognizer: SFSpeechRecognizer,
    continuation: AsyncThrowingStream<Transcript, Error>.Continuation
  ) async {
    // Reset state for a new run.
    self.recognizer = recognizer
    self.continuation = continuation

    latestText = ""
    didYieldFinal = false
    isStopping = false
    didFinish = false
    sawNonSilentAudio = false

    stopTimer?.cancel()
    stopTimer = nil

    let audioEngine = AVAudioEngine()
    self.audioEngine = audioEngine

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    self.request = request

    let input = audioEngine.inputNode
    let format = input.outputFormat(forBus: 0)
    if format.channelCount == 0 {
      finish(.failure(EngineError.noAudioInput))
      return
    }

    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      guard let self else { return }
      Task { await self.handleAudioBuffer(buffer) }
    }

    audioEngine.prepare()
    do {
      try audioEngine.start()
    } catch {
      finish(.failure(error))
      return
    }

    task = recognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self else { return }
      Task { await self.handleRecognition(result: result, error: error) }
    }
  }

  private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
    guard !didFinish else { return }
    guard !isStopping else { return }
    guard let request else { return }

    // Detect whether we ever received non-silent audio during this session.
    // If the mic is broken/muted, Apple Speech can fail with opaque errors; we prefer
    // a direct actionable message.
    if !sawNonSilentAudio {
      let audioBuf = buffer.audioBufferList.pointee.mBuffers
      if let mData = audioBuf.mData, audioBuf.mDataByteSize > 0 {
        let count = Int(audioBuf.mDataByteSize) / MemoryLayout<Int16>.size
        let samples = mData.bindMemory(to: Int16.self, capacity: count)
        for i in 0..<min(count, 512) {
          if samples[i] != 0 {
            sawNonSilentAudio = true
            break
          }
        }
      }
    }

    request.append(buffer)
  }

  private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) async {
    guard !didFinish else { return }

    if let result {
      let text = result.bestTranscription.formattedString
      if text != latestText {
        latestText = text
        continuation?.yield(Transcript(text: text, isFinal: result.isFinal))
      } else if result.isFinal {
        continuation?.yield(Transcript(text: text, isFinal: true))
      }

      if result.isFinal {
        didYieldFinal = true
      }

      if isStopping, result.isFinal {
        finish(.success(text))
        return
      }
    }

    if let error, isStopping {
      finish(.failure(error))
    }
  }

  private func stop() async {
    guard continuation != nil, !didFinish else { return }

    isStopping = true

    request?.endAudio()
    audioEngine?.stop()
    audioEngine?.inputNode.removeTap(onBus: 0)

    scheduleStopTimeout(seconds: 2.0)
  }

  private func scheduleStopTimeout(seconds: Double) {
    stopTimer?.cancel()

    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
    timer.schedule(deadline: .now() + seconds)
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      Task { await self.handleStopTimeout() }
    }
    stopTimer = timer
    timer.resume()
  }

  private func handleStopTimeout() async {
    guard !didFinish else { return }

    let trimmed = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      finish(.success(latestText))
    } else {
      if !sawNonSilentAudio {
        finish(.failure(NSError(
          domain: "AIVoiceKeyboard",
          code: 1001,
          userInfo: [NSLocalizedDescriptionKey: "No audio captured. Check microphone input."]
        )))
      } else {
        finish(.failure(EngineError.noResult))
      }
    }
  }

  private func finish(_ result: Result<String, Error>) {
    guard !didFinish else { return }
    didFinish = true

    stopTimer?.cancel()
    stopTimer = nil

    task?.cancel()
    task = nil

    request = nil
    recognizer = nil

    audioEngine?.stop()
    audioEngine?.inputNode.removeTap(onBus: 0)
    audioEngine = nil

    isStopping = false

    guard let continuation else { return }
    self.continuation = nil

    switch result {
    case .success(let text):
      if !didYieldFinal {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          continuation.yield(Transcript(text: text, isFinal: true))
        }
      }
      continuation.finish()
    case .failure(let error):
      continuation.finish(throwing: error)
    }
  }
}

