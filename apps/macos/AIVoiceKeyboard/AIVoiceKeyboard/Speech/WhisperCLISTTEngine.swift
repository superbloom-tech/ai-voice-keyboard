import AVFoundation
import Foundation
import VoiceKeyboardCore

actor WhisperCLISTTEngine: STTEngine {
  enum EngineError: LocalizedError {
    case alreadyRunning
    case recorderFailed
    case recordingFileNotFound
    case recordingEmpty
    case whisperExecutableNotFound
    case processFailed(exitCode: Int32, stderr: String)
    case timedOut(seconds: Double)
    case outputNotFound(debug: String)
    case noResult

    var errorDescription: String? {
      switch self {
      case .alreadyRunning:
        return "Whisper session already running"
      case .recorderFailed:
        return "Failed to start audio recording"
      case .recordingFileNotFound:
        return "Recording file not found. Check microphone input/device and retry."
      case .recordingEmpty:
        return "No audio captured. Check microphone input/device and retry."
      case .whisperExecutableNotFound:
        return "Whisper CLI not found. Install it (e.g. `brew install openai-whisper`) or set the executable path in Settings."
      case .processFailed(let exitCode, let stderr):
        if stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          return "Whisper CLI failed (exit code: \(exitCode))"
        }
        return "Whisper CLI failed (exit code: \(exitCode)): \(stderr)"
      case .timedOut(let seconds):
        return "Whisper transcription timed out after \(Int(seconds))s. Try a smaller model or increase the timeout in Settings."
      case .outputNotFound(let debug):
        let trimmed = debug.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
          return "Whisper output file not found"
        }
        return "Whisper output file not found. \(trimmed)"
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

    let sampleRate = DefaultAudioInputDevice.nominalSampleRate() ?? 44_100
    if let deviceName = DefaultAudioInputDevice.name() {
      NSLog("[WhisperCLI] Using default input: %@ (nominal sampleRate: %.0f Hz)", deviceName, sampleRate)
    }

    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      // Match the default input device's nominal sample rate when possible; Bluetooth mics (e.g. AirPods)
      // often run at 24kHz and can fail to start if forced to an unsupported rate.
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
    let recordingBytes = try await waitForRecordingBytes(audioURL: audioURL)

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
    process.environment = resolvedSubprocessEnvironment()

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

    if FileManager.default.fileExists(atPath: outFile.path) {
      return try String(contentsOf: outFile, encoding: .utf8)
    }

    // Some whisper versions may change naming; best-effort fallback to a single txt file.
    let outFiles = try? FileManager.default.contentsOfDirectory(at: outDir, includingPropertiesForKeys: nil)
    let txtFiles = outFiles?.filter { $0.pathExtension.lowercased() == "txt" } ?? []
    if txtFiles.count == 1 {
      return try String(contentsOf: txtFiles[0], encoding: .utf8)
    }

    throw EngineError.outputNotFound(debug: buildOutputNotFoundDebug(
      expectedOutFile: outFile,
      outDir: outDir,
      recordingBytes: recordingBytes,
      stdout: result.stdout,
      stderr: result.stderr
    ))
  }

  private func waitForRecordingBytes(audioURL: URL) async throws -> Int64 {
    let fm = FileManager.default
    guard fm.fileExists(atPath: audioURL.path) else {
      throw EngineError.recordingFileNotFound
    }

    // AVAudioRecorder can report `record() == true` while the underlying AudioQueue fails to start.
    // Poll briefly for the file to become non-empty before invoking whisper.
    var lastSize: Int64 = 0
    for _ in 0..<10 {
      lastSize = (try? fm.attributesOfItem(atPath: audioURL.path)[.size] as? NSNumber)?.int64Value ?? 0
      if lastSize > 0 { return lastSize }
      try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
    }

    throw EngineError.recordingEmpty
  }

  private func buildOutputNotFoundDebug(
    expectedOutFile: URL,
    outDir: URL,
    recordingBytes: Int64,
    stdout: String,
    stderr: String
  ) -> String {
    var parts: [String] = []
    parts.append("recordingBytes=\(recordingBytes)")
    parts.append("expected=\(expectedOutFile.lastPathComponent)")

    if let files = try? FileManager.default.contentsOfDirectory(atPath: outDir.path) {
      if files.isEmpty {
        parts.append("outDirFiles=[]")
      } else {
        let joined = files.sorted().prefix(10).joined(separator: ",")
        parts.append("outDirFiles=[\(joined)\(files.count > 10 ? ",..." : "")]")
      }
    }

    let stdoutLine = firstNonEmptyLine(stdout)
    if !stdoutLine.isEmpty {
      parts.append("stdout=\(abbreviate(stdoutLine, maxLen: 300))")
    }
    let stderrLine = firstNonEmptyLine(stderr)
    if !stderrLine.isEmpty {
      parts.append("stderr=\(abbreviate(stderrLine, maxLen: 300))")
    }

    parts.append("tip=Whisper may have skipped the audio (e.g. ffmpeg decode error). Try running `whisper <file>` manually to see full output.")
    return parts.joined(separator: " | ")
  }

  private func firstNonEmptyLine(_ s: String) -> String {
    for line in s.split(whereSeparator: \.isNewline) {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
    }
    return ""
  }

  private func abbreviate(_ s: String, maxLen: Int) -> String {
    guard s.count > maxLen else { return s }
    return String(s.prefix(maxLen)) + "..."
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

  private func resolvedSubprocessEnvironment() -> [String: String] {
    // GUI apps don't reliably inherit user shell PATH, and `openai-whisper` shells out to `ffmpeg`.
    // Ensure Homebrew install locations are on PATH so whisper can find ffmpeg.
    var env = ProcessInfo.processInfo.environment

    let defaultSystemPath = "/usr/bin:/bin:/usr/sbin:/sbin"
    let existingPath = env["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    let basePath = (existingPath?.isEmpty == false) ? existingPath! : defaultSystemPath

    let extraPaths = [
      "/opt/homebrew/bin",
      "/usr/local/bin"
    ]

    // Preserve ordering while de-duplicating.
    var seen: Set<String> = []
    var finalParts: [String] = []

    for part in (extraPaths + basePath.split(separator: ":").map(String.init)) {
      let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      guard !seen.contains(trimmed) else { continue }
      seen.insert(trimmed)
      finalParts.append(trimmed)
    }

    env["PATH"] = finalParts.joined(separator: ":")
    return env
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
