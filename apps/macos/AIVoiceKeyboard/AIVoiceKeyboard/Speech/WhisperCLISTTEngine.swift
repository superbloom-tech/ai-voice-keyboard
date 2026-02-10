import AVFoundation
import Foundation
import VoiceKeyboardCore

actor WhisperCLISTTEngine: STTEngine {
  enum EngineError: LocalizedError {
    case alreadyRunning
    case recorderFailed
    case whisperExecutableNotFound
    case processFailed(exitCode: Int32, stderr: String)
    case timedOut(seconds: Double)
    case outputNotFound
    case noResult

    var errorDescription: String? {
      switch self {
      case .alreadyRunning:
        return "Whisper session already running"
      case .recorderFailed:
        return "Failed to start audio recording"
      case .whisperExecutableNotFound:
        return "Whisper CLI not found. Install it (e.g. `brew install openai-whisper`) or set the executable path in Settings."
      case .processFailed(let exitCode, let stderr):
        if stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          return "Whisper CLI failed (exit code: \(exitCode))"
        }
        return "Whisper CLI failed (exit code: \(exitCode)): \(stderr)"
      case .timedOut(let seconds):
        return "Whisper transcription timed out after \(Int(seconds))s. Try a smaller model or increase the timeout in Settings."
      case .outputNotFound:
        return "Whisper output file not found"
      case .noResult:
        return "No transcription result"
      }
    }
  }

  nonisolated let id: String = "whisper_local"
  nonisolated let displayName: String = "Whisper (Local CLI)"

  private let configuration: WhisperLocalConfiguration

  private var recorder: AVAudioRecorder?
  private var sessionDir: URL?
  private var recordingURL: URL?
  private var continuation: AsyncThrowingStream<Transcript, Error>.Continuation?
  private var isStopping: Bool = false

  init(configuration: WhisperLocalConfiguration) {
    self.configuration = configuration
  }

  func capabilities() async -> STTCapabilities {
    STTCapabilities(
      supportsStreaming: false,
      supportsOnDeviceRecognition: true,
      supportedLocaleIdentifiers: nil
    )
  }

  func streamTranscripts(locale: Locale) async throws -> STTTranscriptStream {
    _ = locale
    guard recorder == nil, continuation == nil, !isStopping else { throw EngineError.alreadyRunning }

    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("avkb-stt-whisper-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let recordingURL = dir.appendingPathComponent("recording.m4a", isDirectory: false)

    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: 16_000,
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
        await self.stopAndTranscribe()
      }
    )
  }

  private func bindContinuation(_ continuation: AsyncThrowingStream<Transcript, Error>.Continuation) {
    self.continuation = continuation
  }

  private func stopAndTranscribe() async {
    guard !isStopping else { return }
    isStopping = true

    let cont = continuation
    continuation = nil

    let dir = sessionDir
    let audioURL = recordingURL

    recorder?.stop()
    recorder = nil

    defer {
      // Best-effort cleanup. Keep failures silent.
      if let dir {
        try? FileManager.default.removeItem(at: dir)
      }
      sessionDir = nil
      recordingURL = nil
      isStopping = false
    }

    guard let cont else { return }
    guard let dir, let audioURL else {
      cont.finish(throwing: EngineError.noResult)
      return
    }

    do {
      let text = try await transcribe(audioURL: audioURL, workingDirectory: dir)
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

  private func transcribe(audioURL: URL, workingDirectory: URL) async throws -> String {
    let outDir = workingDirectory.appendingPathComponent("whisper-out", isDirectory: true)
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
    let language = configuration.language?.trimmingCharacters(in: .whitespacesAndNewlines)

    let (executableURL, prependArgs) = resolveWhisperExecutable()

    var args: [String] = []
    args.append(contentsOf: prependArgs)
    args += [
      audioURL.path,
      "--model", model,
      "--output_dir", outDir.path,
      "--output_format", "txt",
      "--verbose", "False",
      "--task", "transcribe"
    ]
    if let language, !language.isEmpty {
      args += ["--language", language]
    }

    let process = Process()
    process.executableURL = executableURL
    process.arguments = args

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    let timeout = configuration.inferenceTimeoutSeconds
    let result = try await runProcess(process, timeoutSeconds: timeout)

    guard result.exitCode == 0 else {
      throw EngineError.processFailed(exitCode: result.exitCode, stderr: result.stderr)
    }

    let baseName = audioURL.deletingPathExtension().lastPathComponent
    let outFile = outDir.appendingPathComponent("\(baseName).txt", isDirectory: false)

    guard FileManager.default.fileExists(atPath: outFile.path) else {
      throw EngineError.outputNotFound
    }

    return try String(contentsOf: outFile, encoding: .utf8)
  }

  private func resolveWhisperExecutable() -> (URL, [String]) {
    let trimmed = configuration.executablePath?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let trimmed, !trimmed.isEmpty {
      return (URL(fileURLWithPath: trimmed), [])
    }

    let candidates = [
      "/opt/homebrew/bin/whisper",
      "/usr/local/bin/whisper"
    ]

    for path in candidates {
      if FileManager.default.isExecutableFile(atPath: path) {
        return (URL(fileURLWithPath: path), [])
      }
    }

    // Fallback: rely on PATH resolution (e.g. in CI/dev shells).
    return (URL(fileURLWithPath: "/usr/bin/env"), ["whisper"])
  }

  private struct ProcessRunResult: Sendable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
  }

  private func runProcess(_ process: Process, timeoutSeconds: Double) async throws -> ProcessRunResult {
    try await withThrowingTaskGroup(of: ProcessRunResult.self) { group in
      group.addTask {
        try await self.runProcessUntilExit(process)
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
        throw EngineError.timedOut(seconds: timeoutSeconds)
      }

      do {
        let result = try await group.next()!
        group.cancelAll()
        return result
      } catch {
        // Ensure we terminate the process on timeout/errors.
        if process.isRunning {
          process.terminate()
        }
        group.cancelAll()
        throw error
      }
    }
  }

  private func runProcessUntilExit(_ process: Process) async throws -> ProcessRunResult {
    let stdout = process.standardOutput as? Pipe
    let stderr = process.standardError as? Pipe

    do {
      try process.run()
    } catch {
      throw EngineError.whisperExecutableNotFound
    }

    return try await withCheckedThrowingContinuation { continuation in
      process.terminationHandler = { proc in
        let outData = stdout?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        let errData = stderr?.fileHandleForReading.readDataToEndOfFile() ?? Data()

        let outStr = String(data: outData, encoding: .utf8) ?? ""
        let errStr = String(data: errData, encoding: .utf8) ?? ""

        continuation.resume(returning: ProcessRunResult(
          exitCode: proc.terminationStatus,
          stdout: outStr,
          stderr: errStr
        ))
      }
    }
  }
}

