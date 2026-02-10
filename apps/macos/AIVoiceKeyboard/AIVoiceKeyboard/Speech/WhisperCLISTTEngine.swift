import AVFoundation
import Foundation
import VoiceKeyboardCore

actor WhisperCLISTTEngine: STTEngine {
  // Use a reference-type buffer so we can safely append from FileHandle.readabilityHandler
  // without mutating captured vars inside a @Sendable closure (Xcode 15.x strict concurrency).
  private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
      lock.lock()
      data.append(chunk)
      lock.unlock()
    }

    func snapshot() -> Data {
      lock.lock()
      let copy = data
      lock.unlock()
      return copy
    }
  }

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
    guard recorder == nil, continuation == nil, !isStopping else {
      NSLog("[WhisperSTT] streamTranscripts called but already running (recorder=%@, continuation=%@, isStopping=%d)",
            recorder != nil ? "set" : "nil", continuation != nil ? "set" : "nil", isStopping ? 1 : 0)
      throw EngineError.alreadyRunning
    }

    NSLog("[WhisperSTT] Starting new session")

    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("avkb-stt-whisper-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    NSLog("[WhisperSTT] Session directory: %@", dir.path)

    let recordingURL = dir.appendingPathComponent("recording.m4a", isDirectory: false)

    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: 16_000,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    NSLog("[WhisperSTT] Recording settings: format=AAC, sampleRate=16000, channels=1, quality=high")
    NSLog("[WhisperSTT] Recording file: %@", recordingURL.path)

    let recorder = try AVAudioRecorder(url: recordingURL, settings: settings)
    recorder.prepareToRecord()
    guard recorder.record() else {
      NSLog("[WhisperSTT] ERROR: recorder.record() returned false")
      throw EngineError.recorderFailed
    }

    NSLog("[WhisperSTT] Recording started successfully")

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
    guard !isStopping else {
      NSLog("[WhisperSTT] stopAndTranscribe called but already stopping, skipping")
      return
    }
    isStopping = true
    NSLog("[WhisperSTT] Stopping recording and starting transcription")

    let cont = continuation
    continuation = nil

    let dir = sessionDir
    let audioURL = recordingURL

    recorder?.stop()
    recorder = nil
    NSLog("[WhisperSTT] Recorder stopped")

    // Log audio file size
    if let audioURL, FileManager.default.fileExists(atPath: audioURL.path) {
      let attrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path)
      let fileSize = attrs?[.size] as? UInt64 ?? 0
      NSLog("[WhisperSTT] Audio file: %@ (size: %llu bytes)", audioURL.path, fileSize)
    } else {
      NSLog("[WhisperSTT] WARNING: Audio file does not exist at expected path: %@", audioURL?.path ?? "nil")
    }

    defer {
      // Best-effort cleanup. Keep failures silent.
      if let dir {
        NSLog("[WhisperSTT] Cleaning up session directory: %@", dir.path)
        try? FileManager.default.removeItem(at: dir)
      }
      sessionDir = nil
      recordingURL = nil
      isStopping = false
    }

    guard let cont else {
      NSLog("[WhisperSTT] WARNING: No continuation available, cannot deliver result")
      return
    }
    guard let dir, let audioURL else {
      NSLog("[WhisperSTT] ERROR: Missing session dir or audio URL")
      cont.finish(throwing: EngineError.noResult)
      return
    }

    do {
      let text = try await transcribe(audioURL: audioURL, workingDirectory: dir)
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      NSLog("[WhisperSTT] Transcription result: \"%@\" (trimmed length: %d)", trimmed, trimmed.count)
      guard !trimmed.isEmpty else {
        NSLog("[WhisperSTT] ERROR: Transcription result is empty after trimming")
        cont.finish(throwing: EngineError.noResult)
        return
      }

      cont.yield(Transcript(text: text, isFinal: true))
      cont.finish()
      NSLog("[WhisperSTT] Final transcript yielded successfully")
    } catch {
      NSLog("[WhisperSTT] ERROR: Transcription failed: %@", error.localizedDescription)
      cont.finish(throwing: error)
    }
  }

  private func transcribe(audioURL: URL, workingDirectory: URL) async throws -> String {
    let outDir = workingDirectory.appendingPathComponent("whisper-out", isDirectory: true)
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
    let language = configuration.language?.trimmingCharacters(in: .whitespacesAndNewlines)

    NSLog("[WhisperSTT] Configuration: model=%@, language=%@, timeout=%.1fs",
          model, language ?? "(auto-detect)", configuration.inferenceTimeoutSeconds)

    let (executableURL, prependArgs) = resolveWhisperExecutable()
    NSLog("[WhisperSTT] Resolved executable: %@ (prepend args: %@)",
          executableURL.path, prependArgs.joined(separator: " "))

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

    NSLog("[WhisperSTT] Full command: %@ %@", executableURL.path, args.joined(separator: " "))

    let process = Process()
    process.executableURL = executableURL
    process.arguments = args

    // macOS GUI apps launched from Finder/Dock have a minimal PATH that
    // does not include Homebrew directories. Whisper depends on ffmpeg
    // being reachable via PATH, so we inject common Homebrew bin paths.
    var env = ProcessInfo.processInfo.environment
    let homebrewPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
    let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    let missingPaths = homebrewPaths.filter { !currentPath.contains($0) }
    if !missingPaths.isEmpty {
      env["PATH"] = (missingPaths + [currentPath]).joined(separator: ":")
      NSLog("[WhisperSTT] Augmented PATH: %@", env["PATH"]!)
    }
    process.environment = env

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    let timeout = configuration.inferenceTimeoutSeconds
    NSLog("[WhisperSTT] Launching whisper process (timeout: %.1fs)...", timeout)
    let startTime = CFAbsoluteTimeGetCurrent()
    let result = try await runProcess(process, timeoutSeconds: timeout)
    let elapsed = CFAbsoluteTimeGetCurrent() - startTime

    NSLog("[WhisperSTT] Process finished in %.2fs — exit code: %d", elapsed, result.exitCode)
    if !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      NSLog("[WhisperSTT] Process stdout:\n%@", result.stdout)
    }
    if !result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      NSLog("[WhisperSTT] Process stderr:\n%@", result.stderr)
    }

    guard result.exitCode == 0 else {
      NSLog("[WhisperSTT] ERROR: Whisper process failed with exit code %d", result.exitCode)
      throw EngineError.processFailed(exitCode: result.exitCode, stderr: result.stderr)
    }

    // Whisper CLI may exit 0 but skip the file (e.g. when ffmpeg is missing).
    // Detect this by checking stdout for the "Skipping" pattern.
    if result.stdout.contains("Skipping") && result.stdout.contains("FileNotFoundError") {
      NSLog("[WhisperSTT] ERROR: Whisper skipped the audio file (likely missing ffmpeg)")
      throw EngineError.processFailed(exitCode: 0, stderr: "Whisper skipped the audio file: \(result.stdout)")
    }

    let baseName = audioURL.deletingPathExtension().lastPathComponent
    let outFile = outDir.appendingPathComponent("\(baseName).txt", isDirectory: false)
    NSLog("[WhisperSTT] Expected output file: %@", outFile.path)

    guard FileManager.default.fileExists(atPath: outFile.path) else {
      // List what files actually exist in outDir for debugging
      let contents = (try? FileManager.default.contentsOfDirectory(atPath: outDir.path)) ?? []
      NSLog("[WhisperSTT] ERROR: Output file not found. Files in output dir: %@", contents.joined(separator: ", "))
      throw EngineError.outputNotFound
    }

    let outputText = try String(contentsOf: outFile, encoding: .utf8)
    NSLog("[WhisperSTT] Output file content (%d bytes): \"%@\"",
          outputText.utf8.count, outputText.trimmingCharacters(in: .whitespacesAndNewlines))
    return outputText
  }

  private func resolveWhisperExecutable() -> (URL, [String]) {
    let trimmed = configuration.executablePath?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let trimmed, !trimmed.isEmpty {
      NSLog("[WhisperSTT] Using custom executable path: %@", trimmed)
      return (URL(fileURLWithPath: trimmed), [])
    }

    let candidates = [
      "/opt/homebrew/bin/whisper",
      "/usr/local/bin/whisper"
    ]

    for path in candidates {
      if FileManager.default.isExecutableFile(atPath: path) {
        NSLog("[WhisperSTT] Found whisper at: %@", path)
        return (URL(fileURLWithPath: path), [])
      } else {
        NSLog("[WhisperSTT] Candidate not found or not executable: %@", path)
      }
    }

    // Fallback: rely on PATH resolution (e.g. in CI/dev shells).
    NSLog("[WhisperSTT] No direct candidate found, falling back to /usr/bin/env whisper")
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
        NSLog("[WhisperSTT] ERROR: Process timed out after %.1fs", timeoutSeconds)
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
    let stdoutPipe = process.standardOutput as? Pipe
    let stderrPipe = process.standardError as? Pipe

    let outBuffer = LockedDataBuffer()
    let errBuffer = LockedDataBuffer()

    let stdoutHandle = stdoutPipe?.fileHandleForReading
    let stderrHandle = stderrPipe?.fileHandleForReading

    // Drain stdout/stderr while the process is running to avoid deadlock when the pipe buffer fills up.
    stdoutHandle?.readabilityHandler = { handle in
      let chunk = handle.availableData
      guard !chunk.isEmpty else { return }
      outBuffer.append(chunk)
    }
    stderrHandle?.readabilityHandler = { handle in
      let chunk = handle.availableData
      guard !chunk.isEmpty else { return }
      errBuffer.append(chunk)
    }

    let exitCode: Int32 = try await withCheckedThrowingContinuation { continuation in
      process.terminationHandler = { proc in
        continuation.resume(returning: proc.terminationStatus)
      }

      do {
        try process.run()
        NSLog("[WhisperSTT] Process launched (pid: %d)", process.processIdentifier)
      } catch {
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        NSLog("[WhisperSTT] ERROR: Failed to launch process: %@", error.localizedDescription)
        continuation.resume(throwing: EngineError.whisperExecutableNotFound)
      }
    }

    // Stop draining and collect any remaining data.
    stdoutHandle?.readabilityHandler = nil
    stderrHandle?.readabilityHandler = nil

    if let stdoutHandle {
      let tail = stdoutHandle.readDataToEndOfFile()
      if !tail.isEmpty {
        outBuffer.append(tail)
      }
    }
    if let stderrHandle {
      let tail = stderrHandle.readDataToEndOfFile()
      if !tail.isEmpty {
        errBuffer.append(tail)
      }
    }

    let outStr = String(data: outBuffer.snapshot(), encoding: .utf8) ?? ""
    let errStr = String(data: errBuffer.snapshot(), encoding: .utf8) ?? ""

    return ProcessRunResult(
      exitCode: exitCode,
      stdout: outStr,
      stderr: errStr
    )
  }
}
