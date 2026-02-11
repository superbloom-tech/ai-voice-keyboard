import AVFoundation
import Foundation
import VoiceKeyboardCore

enum ElevenLabsAPI {
  static func baseURLV1(_ raw: URL) -> URL {
    // Accept:
    // - https://api.elevenlabs.io
    // - https://api.elevenlabs.io/v1
    // - https://api.elevenlabs.io/v1/
    // - https://api.elevenlabs.io/v1/speech-to-text
    //
    // Also support proxy base URLs that include a path prefix, e.g.:
    // - https://proxy.example.com/elevenlabs (=> .../elevenlabs/v1)
    // - https://proxy.example.com/elevenlabs/v1 (=> unchanged)
    guard var comps = URLComponents(url: raw, resolvingAgainstBaseURL: false) else {
      return raw
    }

    // baseURL should not include query/fragment.
    comps.query = nil
    comps.fragment = nil

    let parts = comps.path.split(separator: "/").map(String.init)

    func makeURL(pathParts: [String]) -> URL {
      comps.path = "/" + pathParts.joined(separator: "/")
      return comps.url ?? raw
    }

    // If the user already included /v1 (or a proxy prefix + /v1), trim to that.
    if let idx = parts.firstIndex(of: "v1") {
      return makeURL(pathParts: Array(parts[0...idx]))
    }

    // If the user pasted the full endpoint, drop the last segment and then append v1.
    if parts.last == "speech-to-text" {
      let prefix = Array(parts.dropLast())
      if let idx = prefix.firstIndex(of: "v1") {
        return makeURL(pathParts: Array(prefix[0...idx]))
      }
      return makeURL(pathParts: prefix + ["v1"])
    }

    // Default: append v1 to whatever base path the user provided.
    return makeURL(pathParts: parts + ["v1"])
  }
}

enum ElevenLabsSpeechToTextResponse {
  struct Chunk: Decodable {
    var text: String
  }

  struct Multichannel: Decodable {
    var transcripts: [Chunk]
  }

  struct DecodeError: LocalizedError {
    var chunkError: Error
    var multichannelError: Error

    var errorDescription: String? {
      "decode failed (chunk: \(chunkError.localizedDescription); multichannel: \(multichannelError.localizedDescription))"
    }
  }

  static func decodeTranscriptText(from data: Data) throws -> String {
    let decoder = JSONDecoder()

    do {
      return try decoder.decode(Chunk.self, from: data).text
    } catch {
      let chunkError = error
      do {
        return try decoder.decode(Multichannel.self, from: data).transcripts.map(\.text).joined(separator: "\n")
      } catch {
        throw DecodeError(chunkError: chunkError, multichannelError: error)
      }
    }
  }
}

actor ElevenLabsRESTSTTEngine: STTEngine {
  enum EngineError: LocalizedError {
    case alreadyRunning
    case recorderFailed
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

  nonisolated let id: String = "elevenlabs_rest"
  nonisolated let displayName: String = "ElevenLabs (REST)"

  private let configuration: ElevenLabsRESTSTTConfiguration

  private var recorder: AVAudioRecorder?
  private var sessionDir: URL?
  private var recordingURL: URL?
  private var continuation: AsyncThrowingStream<Transcript, Error>.Continuation?
  private var isStopping: Bool = false

  init(configuration: ElevenLabsRESTSTTConfiguration) {
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
      .appendingPathComponent("avkb-stt-elevenlabs-rest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let recordingURL = dir.appendingPathComponent("recording.wav", isDirectory: false)

    // Record WAV PCM 16kHz mono for broad compatibility across STT providers.
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: 16_000,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsFloatKey: false,
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

  private func transcribe(audioURL: URL, locale: Locale) async throws -> String {
    let apiKeyId = configuration.apiKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let apiKey = try STTKeychain.load(apiKeyId: apiKeyId),
          !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw EngineError.apiKeyMissing(apiKeyId: apiKeyId)
    }

    let boundary = "Boundary-\(UUID().uuidString)"

    let bodyURL = (sessionDir ?? FileManager.default.temporaryDirectory)
      .appendingPathComponent("multipart-body.bin", isDirectory: false)

    var fields: [(String, String)] = [
      ("model_id", configuration.model),
    ]

    // Best-effort language hint.
    if let lang = locale.language.languageCode?.identifier, !lang.isEmpty {
      fields.append(("language_code", lang))
    }

    try MultipartWriter.write(
      to: bodyURL,
      boundary: boundary,
      fields: fields,
      fileFieldName: "file",
      fileURL: audioURL,
      filename: "recording.wav",
      mimeType: "audio/wav"
    )

    defer { try? FileManager.default.removeItem(at: bodyURL) }

    let endpoint = ElevenLabsAPI.baseURLV1(configuration.baseURL).appendingPathComponent("speech-to-text")

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = configuration.requestTimeoutSeconds
    request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    let (data, response) = try await URLSession.shared.upload(for: request, fromFile: bodyURL)

    guard let http = response as? HTTPURLResponse else {
      throw EngineError.invalidResponse
    }

    guard (200..<300).contains(http.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw EngineError.httpError(statusCode: http.statusCode, body: body)
    }

    do {
      return try ElevenLabsSpeechToTextResponse.decodeTranscriptText(from: data)
    } catch {
#if DEBUG
      let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8 body: \(data.count) bytes>"
      let limit = 2048
      let truncated = rawBody.count > limit ? String(rawBody.prefix(limit)) + "…" : rawBody
      NSLog("[STT][ElevenLabs] Response decode failed: %@; body(truncated)=%@", error.localizedDescription, truncated)
#else
      // Avoid logging response bodies (may include user content) in production builds.
      NSLog("[STT][ElevenLabs] Response decode failed: %@ (bodyLength=%d bytes)", error.localizedDescription, data.count)
#endif
      throw EngineError.invalidResponse
    }
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
        // Prevent header injection if this writer gets reused with dynamic names/filenames.
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
