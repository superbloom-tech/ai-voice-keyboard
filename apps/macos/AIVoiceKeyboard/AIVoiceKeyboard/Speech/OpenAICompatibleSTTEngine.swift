import AVFoundation
import Foundation
import VoiceKeyboardCore

actor OpenAICompatibleSTTEngine: STTEngine {
  enum EngineError: LocalizedError {
    case alreadyRunning
    case recorderFailed
    case recordingFileNotFound
    case recordingEmpty
    case apiKeyMissing(apiKeyId: String)
    case httpError(statusCode: Int, body: String)
    case invalidResponse
    case noResult

    var errorDescription: String? {
      switch self {
      case .alreadyRunning:
        return "STT session already running"
      case .recorderFailed:
        return "Failed to start audio recording"
      case .recordingFileNotFound:
        return "Recording file not found. Check microphone input/device and retry."
      case .recordingEmpty:
        return "No audio captured. Check microphone input/device and retry."
      case .apiKeyMissing(let apiKeyId):
        return "Missing STT API key for id: \(apiKeyId). Configure it in Settings."
      case .httpError(let statusCode, let body):
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          return "STT request failed (HTTP \(statusCode))"
        }
        return "STT request failed (HTTP \(statusCode)): \(body)"
      case .invalidResponse:
        return "Invalid STT response"
      case .noResult:
        return "No transcription result"
      }
    }
  }

  nonisolated let id: String = "openai_compatible"
  nonisolated let displayName: String = "Remote STT (OpenAI-compatible)"

  private let configuration: OpenAICompatibleSTTConfiguration

  private var recorder: AVAudioRecorder?
  private var sessionDir: URL?
  private var recordingURL: URL?
  private var continuation: AsyncThrowingStream<Transcript, Error>.Continuation?
  private var isStopping: Bool = false

  init(configuration: OpenAICompatibleSTTConfiguration) {
    self.configuration = configuration
  }

  func capabilities() async -> STTCapabilities {
    STTCapabilities(
      supportsStreaming: false,
      supportsOnDeviceRecognition: false,
      supportedLocaleIdentifiers: nil
    )
  }

  func streamTranscripts(locale: Locale) async throws -> STTTranscriptStream {
    _ = locale
    guard recorder == nil, continuation == nil, !isStopping else { throw EngineError.alreadyRunning }

    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("avkb-stt-openai-compatible-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let recordingURL = dir.appendingPathComponent("recording.m4a", isDirectory: false)

    let sampleRate = DefaultAudioInputDevice.nominalSampleRate() ?? 44_100
    if let deviceName = DefaultAudioInputDevice.name() {
      NSLog("[OpenAICompatibleSTT] Using default input: %@ (nominal sampleRate: %.0f Hz)", deviceName, sampleRate)
    }

    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      // Match the default input device's nominal sample rate when possible.
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    let recorder = try AVAudioRecorder(url: recordingURL, settings: settings)
    recorder.prepareToRecord()
    guard recorder.record() else { throw EngineError.recorderFailed }

    self.sessionDir = dir
    self.recordingURL = recordingURL
    self.recorder = recorder

    return STTTranscriptStream(
      makeStream: { continuation in
        Task { await self.bindContinuation(continuation) }
      },
      cancel: {
        await self.stopAndTranscribe(locale: locale)
      }
    )
  }

  private func bindContinuation(_ continuation: AsyncThrowingStream<Transcript, Error>.Continuation) {
    self.continuation = continuation
  }

  private func stopAndTranscribe(locale: Locale) async {
    guard !isStopping else { return }
    isStopping = true

    let cont = continuation
    continuation = nil

    let dir = sessionDir
    let audioURL = recordingURL

    recorder?.stop()
    recorder = nil

    defer {
      // Best-effort cleanup.
      if let dir {
        try? FileManager.default.removeItem(at: dir)
      }
      sessionDir = nil
      recordingURL = nil
      isStopping = false
    }

    guard let cont else { return }
    guard let audioURL else {
      cont.finish(throwing: EngineError.noResult)
      return
    }

    do {
      let text = try await transcribe(audioURL: audioURL, locale: locale)
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        cont.finish(throwing: EngineError.noResult)
        return
      }
      cont.yield(Transcript(text: text, isFinal: true))
      cont.finish()
    } catch {
      cont.finish(throwing: error)
    }
  }

  private struct TranscriptionResponse: Decodable {
    var text: String
  }

  private func transcribe(audioURL: URL, locale: Locale) async throws -> String {
    _ = try await waitForRecordingBytes(audioURL: audioURL)

    let apiKeyId = configuration.apiKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let apiKey = try STTKeychain.load(apiKeyId: apiKeyId),
          !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw EngineError.apiKeyMissing(apiKeyId: apiKeyId)
    }

    let boundary = "Boundary-\(UUID().uuidString)"

    let bodyURL = (sessionDir ?? FileManager.default.temporaryDirectory)
      .appendingPathComponent("multipart-body.bin", isDirectory: false)

    var fields: [(String, String)] = [
      ("model", configuration.model)
    ]

    // Best-effort language hint.
    if let lang = locale.languageCode, !lang.isEmpty {
      fields.append(("language", lang))
    }

    try MultipartWriter.write(
      to: bodyURL,
      boundary: boundary,
      fields: fields,
      fileFieldName: "file",
      fileURL: audioURL,
      filename: "recording.m4a",
      mimeType: "audio/mp4"
    )

    defer { try? FileManager.default.removeItem(at: bodyURL) }

    let endpoint = configuration.baseURL.appendingPathComponent("audio/transcriptions")

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = configuration.requestTimeoutSeconds
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    let (data, response) = try await URLSession.shared.upload(for: request, fromFile: bodyURL)

    guard let http = response as? HTTPURLResponse else {
      throw EngineError.invalidResponse
    }

    guard (200..<300).contains(http.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw EngineError.httpError(statusCode: http.statusCode, body: body)
    }

    let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
    return decoded.text
  }

  private func waitForRecordingBytes(audioURL: URL) async throws -> Int64 {
    let fm = FileManager.default
    guard fm.fileExists(atPath: audioURL.path) else {
      throw EngineError.recordingFileNotFound
    }

    var lastSize: Int64 = 0
    for _ in 0..<10 {
      lastSize = (try? fm.attributesOfItem(atPath: audioURL.path)[.size] as? NSNumber)?.int64Value ?? 0
      if lastSize > 0 { return lastSize }
      try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
    }

    throw EngineError.recordingEmpty
  }

  private enum MultipartWriter {
    static func write(
      to url: URL,
      boundary: String,
      fields: [(String, String)],
      fileFieldName: String,
      fileURL: URL,
      filename: String,
      mimeType: String
    ) throws {
      FileManager.default.createFile(atPath: url.path, contents: nil)
      let handle = try FileHandle(forWritingTo: url)
      defer { try? handle.close() }

      func writeString(_ s: String) throws {
        if let data = s.data(using: .utf8) {
          try handle.write(contentsOf: data)
        }
      }

      for (name, value) in fields {
        try writeString("--\(boundary)\r\n")
        try writeString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        try writeString(value)
        try writeString("\r\n")
      }

      try writeString("--\(boundary)\r\n")
      try writeString("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(filename)\"\r\n")
      try writeString("Content-Type: \(mimeType)\r\n\r\n")

      let readHandle = try FileHandle(forReadingFrom: fileURL)
      defer { try? readHandle.close() }

      while true {
        let chunk = try readHandle.read(upToCount: 64 * 1024) ?? Data()
        if chunk.isEmpty { break }
        try handle.write(contentsOf: chunk)
      }

      try writeString("\r\n")
      try writeString("--\(boundary)--\r\n")
    }
  }
}
