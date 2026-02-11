import AVFoundation
import Foundation
import VoiceKeyboardCore

actor SonioxRESTSTTEngine: STTEngine {
  enum EngineError: LocalizedError {
    case alreadyRunning
    case recorderFailed
    case apiKeyMissing(apiKeyId: String)
    case httpError(statusCode: Int, body: String)
    case invalidResponse
    case transcriptionFailed(message: String?)
    case timedOut(seconds: Double)
    case noResult

    var errorDescription: String? {
      switch self {
      case .alreadyRunning:
        return "STT session already running"
      case .recorderFailed:
        return "Failed to start audio recording"
      case .apiKeyMissing(let apiKeyId):
        return "Missing Soniox API key for id: \(apiKeyId). Configure it in Settings."
      case .httpError(let statusCode, let body):
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          return "Soniox request failed (HTTP \(statusCode))"
        }
        return "Soniox request failed (HTTP \(statusCode)): \(body)"
      case .invalidResponse:
        return "Invalid Soniox response"
      case .transcriptionFailed(let message):
        if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          return "Soniox transcription failed: \(message)"
        }
        return "Soniox transcription failed"
      case .timedOut(let seconds):
        return "Soniox transcription timed out after \(Int(seconds))s."
      case .noResult:
        return "No transcription result"
      }
    }
  }

  nonisolated let id: String = "soniox_rest"
  nonisolated let displayName: String = "Soniox (REST)"

  private let configuration: SonioxRESTSTTConfiguration

  private var recorder: AVAudioRecorder?
  private var sessionDir: URL?
  private var recordingURL: URL?
  private var continuation: AsyncThrowingStream<Transcript, Error>.Continuation?
  private var isStopping: Bool = false

  init(configuration: SonioxRESTSTTConfiguration) {
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
    guard recorder == nil, continuation == nil, !isStopping else { throw EngineError.alreadyRunning }

    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("avkb-stt-soniox-rest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let recordingURL = dir.appendingPathComponent("recording.wav", isDirectory: false)

    // Soniox auto-detects WAV; use a simple 16kHz mono PCM WAV to reduce format ambiguity.
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: 16_000,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false
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

  private func transcribe(audioURL: URL, locale: Locale) async throws -> String {
    let apiKeyId = configuration.apiKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let apiKey = try STTKeychain.load(apiKeyId: apiKeyId),
          !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw EngineError.apiKeyMissing(apiKeyId: apiKeyId)
    }

    let fileId = try await uploadFile(audioURL: audioURL, apiKey: apiKey)
    let transcriptionId = try await createTranscription(fileId: fileId, locale: locale, apiKey: apiKey)
    try await waitForTranscription(transcriptionId: transcriptionId, apiKey: apiKey)
    return try await fetchTranscript(transcriptionId: transcriptionId, apiKey: apiKey)
  }

  private func apiBaseURL() -> URL {
    // Allow either https://api.soniox.com or https://api.soniox.com/v1 in settings.
    let base = configuration.baseURL
    if base.pathComponents.last == "v1" {
      return base
    }
    return base.appendingPathComponent("v1")
  }

  private func uploadFile(audioURL: URL, apiKey: String) async throws -> String {
    struct UploadedFile: Decodable { var id: String }

    let boundary = "Boundary-\(UUID().uuidString)"
    let bodyURL = (sessionDir ?? FileManager.default.temporaryDirectory)
      .appendingPathComponent("soniox-upload-body.bin", isDirectory: false)

    try MultipartWriter.write(
      to: bodyURL,
      boundary: boundary,
      fields: [("client_reference_id", "avkb-\(UUID().uuidString)")],
      fileFieldName: "file",
      fileURL: audioURL,
      filename: "recording.wav",
      mimeType: "audio/wav"
    )
    defer { try? FileManager.default.removeItem(at: bodyURL) }

    let endpoint = apiBaseURL().appendingPathComponent("files")
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = configuration.requestTimeoutSeconds
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    let (data, response) = try await URLSession.shared.upload(for: request, fromFile: bodyURL)
    guard let http = response as? HTTPURLResponse else { throw EngineError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw EngineError.httpError(statusCode: http.statusCode, body: body)
    }

    let decoded = try JSONDecoder().decode(UploadedFile.self, from: data)
    return decoded.id
  }

  private func createTranscription(fileId: String, locale: Locale, apiKey: String) async throws -> String {
    struct Payload: Encodable {
      var model: String
      var fileId: String
      var languageHints: [String]?

      enum CodingKeys: String, CodingKey {
        case model
        case fileId = "file_id"
        case languageHints = "language_hints"
      }
    }

    struct Created: Decodable { var id: String }

    let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
    let lang = locale.language.languageCode?.identifier
    let hints = (lang?.isEmpty == false) ? [lang!] : nil

    let payload = Payload(model: model, fileId: fileId, languageHints: hints)
    let data = try JSONEncoder().encode(payload)

    let endpoint = apiBaseURL().appendingPathComponent("transcriptions")
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = configuration.requestTimeoutSeconds
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let (respData, response) = try await URLSession.shared.upload(for: request, from: data)
    guard let http = response as? HTTPURLResponse else { throw EngineError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      let body = String(data: respData, encoding: .utf8) ?? ""
      throw EngineError.httpError(statusCode: http.statusCode, body: body)
    }

    let decoded = try JSONDecoder().decode(Created.self, from: respData)
    return decoded.id
  }

  private func waitForTranscription(transcriptionId: String, apiKey: String) async throws {
    struct StatusResponse: Decodable {
      var status: String
      var errorMessage: String?

      enum CodingKeys: String, CodingKey {
        case status
        case errorMessage = "error_message"
      }
    }

    let deadline = Date().addingTimeInterval(configuration.requestTimeoutSeconds)
    let endpoint = apiBaseURL().appendingPathComponent("transcriptions").appendingPathComponent(transcriptionId)

    while true {
      if Date() > deadline {
        throw EngineError.timedOut(seconds: configuration.requestTimeoutSeconds)
      }

      var request = URLRequest(url: endpoint)
      request.httpMethod = "GET"
      request.timeoutInterval = configuration.requestTimeoutSeconds
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse else { throw EngineError.invalidResponse }
      guard (200..<300).contains(http.statusCode) else {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw EngineError.httpError(statusCode: http.statusCode, body: body)
      }

      let decoded = try JSONDecoder().decode(StatusResponse.self, from: data)
      switch decoded.status {
      case "completed":
        return
      case "error":
        throw EngineError.transcriptionFailed(message: decoded.errorMessage)
      default:
        // queued / processing
        try? await Task.sleep(nanoseconds: 500_000_000)
      }
    }
  }

  private func fetchTranscript(transcriptionId: String, apiKey: String) async throws -> String {
    struct TranscriptResponse: Decodable { var text: String }

    let endpoint = apiBaseURL()
      .appendingPathComponent("transcriptions")
      .appendingPathComponent(transcriptionId)
      .appendingPathComponent("transcript")

    var request = URLRequest(url: endpoint)
    request.httpMethod = "GET"
    request.timeoutInterval = configuration.requestTimeoutSeconds
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw EngineError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw EngineError.httpError(statusCode: http.statusCode, body: body)
    }

    let decoded = try JSONDecoder().decode(TranscriptResponse.self, from: data)
    return decoded.text
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

      func sanitizeDispositionValue(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "\r", with: "")
        out = out.replacingOccurrences(of: "\n", with: "")
        out = out.replacingOccurrences(of: "\"", with: "'")
        return out
      }

      for (name, value) in fields {
        let safeName = sanitizeDispositionValue(name)
        try writeString("--\(boundary)\r\n")
        try writeString("Content-Disposition: form-data; name=\"\(safeName)\"\r\n\r\n")
        try writeString(value)
        try writeString("\r\n")
      }

      let safeFileFieldName = sanitizeDispositionValue(fileFieldName)
      let safeFilename = sanitizeDispositionValue(filename)
      try writeString("--\(boundary)\r\n")
      try writeString("Content-Disposition: form-data; name=\"\(safeFileFieldName)\"; filename=\"\(safeFilename)\"\r\n")
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

