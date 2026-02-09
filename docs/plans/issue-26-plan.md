# Issue #26 Implementation Plan: Insert Post-Processing Pipeline

## Overview

Add a pluggable post-processing pipeline between STT transcription and text insertion, supporting:
- **v0**: Rule-based cleaning (deterministic, low-latency)
- **v1**: Optional lightweight model refinement (configurable, with timeout/fallback)
- Configurable enable/disable
- History tracking of both raw and processed text

## Technical Approach

### 1. Architecture Design

**Core Abstraction: PostProcessor Protocol**

```swift
protocol PostProcessor {
  /// Process transcribed text with optional cancellation/timeout
  /// - Parameters:
  ///   - text: Raw transcribed text
  ///   - timeout: Maximum processing time
  /// - Returns: Processed text
  /// - Throws: PostProcessingError if processing fails
  func process(text: String, timeout: TimeInterval) async throws -> String
}

enum PostProcessingError: LocalizedError {
  case timeout
  case cancelled
  case processingFailed(underlying: Error)
  
  var errorDescription: String? {
    switch self {
    case .timeout:
      return "Post-processing timed out"
    case .cancelled:
      return "Post-processing was cancelled"
    case .processingFailed(let error):
      return "Post-processing failed: \(error.localizedDescription)"
    }
  }
}
```

**Pipeline Composition**

```swift
final class PostProcessingPipeline {
  private let processors: [PostProcessor]
  private let fallbackBehavior: FallbackBehavior
  
  enum FallbackBehavior {
    case returnOriginal  // If any processor fails, return original text
    case returnLastValid // Return the last successfully processed text
    case throwError      // Propagate the error
  }
  
  init(processors: [PostProcessor], fallbackBehavior: FallbackBehavior = .returnOriginal) {
    self.processors = processors
    self.fallbackBehavior = fallbackBehavior
  }
  
  func process(text: String, timeout: TimeInterval) async throws -> ProcessingResult {
    var current = text
    var steps: [ProcessingStep] = []
    
    for processor in processors {
      let stepStart = Date()
      do {
        let processed = try await processor.process(text: current, timeout: timeout)
        let stepDuration = Date().timeIntervalSince(stepStart)
        steps.append(ProcessingStep(
          processorName: String(describing: type(of: processor)),
          input: current,
          output: processed,
          duration: stepDuration,
          success: true
        ))
        current = processed
      } catch {
        let stepDuration = Date().timeIntervalSince(stepStart)
        steps.append(ProcessingStep(
          processorName: String(describing: type(of: processor)),
          input: current,
          output: nil,
          duration: stepDuration,
          success: false,
          error: error
        ))
        
        switch fallbackBehavior {
        case .returnOriginal:
          return ProcessingResult(originalText: text, finalText: text, steps: steps)
        case .returnLastValid:
          return ProcessingResult(originalText: text, finalText: current, steps: steps)
        case .throwError:
          throw error
        }
      }
    }
    
    return ProcessingResult(originalText: text, finalText: current, steps: steps)
  }
}

struct ProcessingResult {
  let originalText: String
  let finalText: String
  let steps: [ProcessingStep]
}

struct ProcessingStep {
  let processorName: String
  let input: String
  let output: String?
  let duration: TimeInterval
  let success: Bool
  let error: Error?
}
```

### 2. v0: Rule-Based Cleaner

**Implementation: TextCleaner**

```swift
final class TextCleaner: PostProcessor {
  struct CleaningRules: OptionSet {
    let rawValue: Int
    
    static let trimWhitespace = CleaningRules(rawValue: 1 << 0)
    static let collapseWhitespace = CleaningRules(rawValue: 1 << 1)
    static let fixBasicPunctuation = CleaningRules(rawValue: 1 << 2)
    static let fixCapitalization = CleaningRules(rawValue: 1 << 3)
    static let removeFillerWords = CleaningRules(rawValue: 1 << 4)
    
    static let basic: CleaningRules = [.trimWhitespace, .collapseWhitespace]
    static let standard: CleaningRules = [.trimWhitespace, .collapseWhitespace, .fixBasicPunctuation]
    static let aggressive: CleaningRules = [.trimWhitespace, .collapseWhitespace, .fixBasicPunctuation, .fixCapitalization, .removeFillerWords]
  }
  
  private let rules: CleaningRules
  
  init(rules: CleaningRules = .standard) {
    self.rules = rules
  }
  
  func process(text: String, timeout: TimeInterval) async throws -> String {
    var result = text
    
    if rules.contains(.trimWhitespace) {
      result = result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    if rules.contains(.collapseWhitespace) {
      result = result.replacingOccurrences(
        of: "\\s+",
        with: " ",
        options: .regularExpression
      )
    }
    
    if rules.contains(.fixBasicPunctuation) {
      // Remove space before punctuation
      result = result.replacingOccurrences(
        of: "\\s+([.,!?;:])",
        with: "$1",
        options: .regularExpression
      )
      
      // Ensure space after punctuation (except at end)
      result = result.replacingOccurrences(
        of: "([.,!?;:])([^\\s])",
        with: "$1 $2",
        options: .regularExpression
      )
    }
    
    if rules.contains(.fixCapitalization) {
      // Capitalize first letter
      if let first = result.first {
        result = first.uppercased() + result.dropFirst()
      }
      
      // Capitalize after sentence-ending punctuation
      result = result.replacingOccurrences(
        of: "([.!?])\\s+([a-z])",
        with: "$1 $2",
        options: .regularExpression
      ) { match in
        let range = match.range(at: 2)
        let char = String(result[range]).uppercased()
        return match.replacingCharacters(in: range, with: char)
      }
    }
    
    if rules.contains(.removeFillerWords) {
      // Remove common filler words (um, uh, like, you know, etc.)
      let fillerPattern = "\\b(um|uh|like|you know|sort of|kind of)\\b"
      result = result.replacingOccurrences(
        of: fillerPattern,
        with: "",
        options: [.regularExpression, .caseInsensitive]
      )
      
      // Clean up any double spaces created by removal
      result = result.replacingOccurrences(
        of: "\\s+",
        with: " ",
        options: .regularExpression
      ).trimmingCharacters(in: .whitespaces)
    }
    
    return result
  }
}
```

### 3. v1: Lightweight Model Refinement (Optional)

**Implementation: LLMRefiner**

```swift
final class LLMRefiner: PostProcessor {
  private let apiClient: LLMAPIClient
  private let systemPrompt: String
  
  init(apiClient: LLMAPIClient, systemPrompt: String? = nil) {
    self.apiClient = apiClient
    self.systemPrompt = systemPrompt ?? Self.defaultSystemPrompt
  }
  
  private static let defaultSystemPrompt = """
    You are a text refinement assistant. Your task is to:
    1. Fix obvious transcription errors
    2. Improve grammar and punctuation
    3. Maintain the original meaning and tone
    4. Keep the text concise
    
    Return ONLY the refined text, no explanations.
    """
  
  func process(text: String, timeout: TimeInterval) async throws -> String {
    // Use Task.withTimeout for cancellation support
    return try await withThrowingTaskGroup(of: String.self) { group in
      group.addTask {
        try await self.apiClient.refine(
          text: text,
          systemPrompt: self.systemPrompt
        )
      }
      
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        throw PostProcessingError.timeout
      }
      
      // Return the first result (either completion or timeout)
      guard let result = try await group.next() else {
        throw PostProcessingError.cancelled
      }
      
      group.cancelAll()
      return result
    }
  }
}

// Placeholder for LLM API client
protocol LLMAPIClient {
  func refine(text: String, systemPrompt: String) async throws -> String
}
```

### 4. Configuration System

**PostProcessingConfig**

```swift
struct PostProcessingConfig: Codable {
  var enabled: Bool
  var cleanerEnabled: Bool
  var cleanerRules: TextCleaner.CleaningRules
  var refinerEnabled: Bool
  var refinerTimeout: TimeInterval
  var refinerModel: String?
  var fallbackBehavior: PostProcessingPipeline.FallbackBehavior
  
  static let `default` = PostProcessingConfig(
    enabled: true,
    cleanerEnabled: true,
    cleanerRules: .standard,
    refinerEnabled: false,
    refinerTimeout: 2.0,
    refinerModel: nil,
    fallbackBehavior: .returnOriginal
  )
  
  static let v0Only = PostProcessingConfig(
    enabled: true,
    cleanerEnabled: true,
    cleanerRules: .standard,
    refinerEnabled: false,
    refinerTimeout: 2.0,
    refinerModel: nil,
    fallbackBehavior: .returnOriginal
  )
}

// UserDefaults integration
extension PostProcessingConfig {
  private static let key = "avkb.postProcessing.config"
  
  static func load() -> PostProcessingConfig {
    guard let data = UserDefaults.standard.data(forKey: key),
          let config = try? JSONDecoder().decode(PostProcessingConfig.self, from: data) else {
      return .default
    }
    return config
  }
  
  func save() {
    guard let data = try? JSONEncoder().encode(self) else { return }
    UserDefaults.standard.set(data, forKey: key)
  }
}
```

### 5. Integration into AppDelegate

**Modify stopTranscriptionAndInsert()**

```swift
// In AppDelegate
private var postProcessingPipeline: PostProcessingPipeline?

// In init() or applicationDidFinishLaunching()
private func setupPostProcessingPipeline() {
  let config = PostProcessingConfig.load()
  
  guard config.enabled else {
    postProcessingPipeline = nil
    return
  }
  
  var processors: [PostProcessor] = []
  
  if config.cleanerEnabled {
    processors.append(TextCleaner(rules: config.cleanerRules))
  }
  
  if config.refinerEnabled, let apiClient = createLLMAPIClient(model: config.refinerModel) {
    processors.append(LLMRefiner(apiClient: apiClient))
  }
  
  postProcessingPipeline = PostProcessingPipeline(
    processors: processors,
    fallbackBehavior: config.fallbackBehavior
  )
}

private func stopTranscriptionAndInsert() async throws -> String {
  guard let transcriber else {
    throw NSError(domain: "AIVoiceKeyboard", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable"])
  }

  let rawText = try await transcriber.stop(timeoutSeconds: 2.0)
  
  // Apply post-processing if enabled
  let finalText: String
  let processingResult: ProcessingResult?
  
  if let pipeline = postProcessingPipeline {
    let result = try await pipeline.process(text: rawText, timeout: 5.0)
    finalText = result.finalText
    processingResult = result
  } else {
    finalText = rawText
    processingResult = nil
  }

  // Capture a fresh snapshot so the user can restore whatever they had right before this insert.
  lastClipboardSnapshot = PasteboardSnapshot.capture(from: .general)
  rebuildHistoryMenu()

  try inserter.insert(text: finalText)
  
  // Return the final text for history tracking
  return finalText
}
```

### 6. Enhanced History Tracking

**Update HistoryEntry**

```swift
struct HistoryEntry: Identifiable, Codable, Sendable {
  let id: UUID
  let mode: HistoryMode
  let text: String  // Final inserted text
  let rawText: String?  // Original transcription (if post-processing was applied)
  let processingSteps: [ProcessingStepRecord]?  // Optional processing metadata
  let createdAt: Date

  init(
    id: UUID = UUID(),
    mode: HistoryMode,
    text: String,
    rawText: String? = nil,
    processingSteps: [ProcessingStepRecord]? = nil,
    createdAt: Date = Date()
  ) {
    self.id = id
    self.mode = mode
    self.text = text
    self.rawText = rawText
    self.processingSteps = processingSteps
    self.createdAt = createdAt
  }
}

struct ProcessingStepRecord: Codable, Sendable {
  let processorName: String
  let duration: TimeInterval
  let success: Bool
}
```

**Update HistoryStore.append()**

```swift
func append(
  mode: HistoryMode,
  text: String,
  rawText: String? = nil,
  processingSteps: [ProcessingStepRecord]? = nil
) {
  let entry = HistoryEntry(
    mode: mode,
    text: text,
    rawText: rawText,
    processingSteps: processingSteps
  )
  entries.insert(entry, at: 0)
  if entries.count > maxEntries {
    entries.removeLast(entries.count - maxEntries)
  }
  saveToDiskBestEffort()
}
```

**Update AppDelegate history tracking**

```swift
// In stopTranscriptionAndInsert()
if !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
  let stepRecords = processingResult?.steps.map { step in
    ProcessingStepRecord(
      processorName: step.processorName,
      duration: step.duration,
      success: step.success
    )
  }
  
  self.historyStore.append(
    mode: .insert,
    text: finalText,
    rawText: processingResult != nil ? rawText : nil,
    processingSteps: stepRecords
  )
}
```

## Implementation Steps

### Phase 1: Core Infrastructure (Priority: High)

1. **Create PostProcessor protocol and pipeline** (`PostProcessing/PostProcessor.swift`)
   - Define `PostProcessor` protocol
   - Implement `PostProcessingPipeline` with composition and fallback logic
   - Add `ProcessingResult` and `ProcessingStep` types

2. **Implement TextCleaner** (`PostProcessing/TextCleaner.swift`)
   - Implement rule-based cleaning with `CleaningRules` option set
   - Cover: trim, collapse whitespace, fix punctuation, capitalization, filler words
   - Add unit tests for each rule

3. **Add Configuration System** (`PostProcessing/PostProcessingConfig.swift`)
   - Define `PostProcessingConfig` struct
   - Add UserDefaults persistence
   - Provide preset configurations (default, v0Only)

### Phase 2: Integration (Priority: High)

4. **Integrate into AppDelegate**
   - Add `postProcessingPipeline` property
   - Implement `setupPostProcessingPipeline()` in init/launch
   - Modify `stopTranscriptionAndInsert()` to use pipeline
   - Handle errors gracefully with fallback to raw text

5. **Enhance History Tracking**
   - Update `HistoryEntry` to include `rawText` and `processingSteps`
   - Update `HistoryStore.append()` signature
   - Modify history recording in `stopTranscriptionAndInsert()`
   - Ensure backward compatibility with existing history files

### Phase 3: v1 LLM Refinement (Priority: Medium, Optional)

6. **Implement LLMRefiner** (`PostProcessing/LLMRefiner.swift`)
   - Define `LLMAPIClient` protocol
   - Implement `LLMRefiner` with timeout/cancellation
   - Create placeholder/mock implementation for testing

7. **Add LLM API Integration** (if implementing v1)
   - Choose API provider (OpenAI, Anthropic, local model)
   - Implement `LLMAPIClient` conformance
   - Add API key configuration
   - Handle rate limits and errors

### Phase 4: UI & Settings (Priority: Low)

8. **Add Settings UI** (optional for v0)
   - Add post-processing toggle in Settings window
   - Add cleaner rules configuration
   - Add refiner enable/timeout configuration
   - Show processing stats in history menu (optional)

### Phase 5: Testing & Polish (Priority: High)

9. **Unit Tests**
   - Test `TextCleaner` with various inputs
   - Test `PostProcessingPipeline` composition and fallback
   - Test configuration persistence

10. **Integration Tests**
    - Test full Insert flow with post-processing
    - Test timeout/cancellation behavior
    - Test history tracking with raw/processed text

11. **Performance Testing**
    - Measure latency impact of TextCleaner (should be <10ms)
    - Measure LLMRefiner timeout behavior
    - Ensure no blocking on main thread

## Files to Create/Modify

### New Files

```
apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/PostProcessing/
├── PostProcessor.swift              # Protocol + Pipeline + Result types
├── TextCleaner.swift                # v0 rule-based cleaner
├── PostProcessingConfig.swift       # Configuration + persistence
└── LLMRefiner.swift                 # v1 optional LLM refinement (future)

apps/macos/AIVoiceKeyboard/AIVoiceKeyboardTests/PostProcessing/
├── TextCleanerTests.swift
├── PostProcessingPipelineTests.swift
└── PostProcessingConfigTests.swift
```

### Modified Files

```
apps/macos/AIVoiceKeyboard/AIVoiceKeyboard/AppDelegate.swift
- Add postProcessingPipeline property
- Add setupPostProcessingPipeline() method
- Modify stopTranscriptionAndInsert() to use pipeline
- Update history tracking with raw/processed text
- Update HistoryEntry struct
- Update HistoryStore.append() signature
```

## Potential Risks & Mitigations

### Risk 1: Performance Impact
- **Mitigation**: TextCleaner is pure string manipulation, should be <10ms
- **Mitigation**: LLMRefiner has timeout (1-2s) with fallback to original text
- **Mitigation**: All processing is async, doesn't block UI

### Risk 2: Breaking Existing History
- **Mitigation**: Make `rawText` and `processingSteps` optional in `HistoryEntry`
- **Mitigation**: Existing history files will decode successfully (new fields are nil)
- **Mitigation**: Add migration test to verify backward compatibility

### Risk 3: LLM API Failures
- **Mitigation**: v1 is optional and disabled by default
- **Mitigation**: Timeout + fallback ensures Insert always works
- **Mitigation**: Clear error messages in UI

### Risk 4: Configuration Complexity
- **Mitigation**: Provide sensible defaults (v0 only, standard rules)
- **Mitigation**: Keep UI simple (toggle + preset selection)
- **Mitigation**: Advanced settings can be added later

## Testing Strategy

### Unit Tests
- TextCleaner: Test each rule independently and in combination
- PostProcessingPipeline: Test composition, fallback behaviors, error handling
- PostProcessingConfig: Test persistence and presets

### Integration Tests
- Full Insert flow with post-processing enabled/disabled
- Timeout and cancellation behavior
- History tracking with raw/processed text

### Manual Testing
- Test with various speech inputs (clean, messy, with filler words)
- Test with different cleaner rule combinations
- Verify history shows both raw and processed text
- Test performance impact (should be imperceptible)

## Success Criteria

✅ Post-processing can be enabled/disabled via configuration
✅ v0 TextCleaner covers: trim, collapse whitespace, fix punctuation, capitalization
✅ Processing has timeout and fallback (never breaks Insert)
✅ History tracks both raw transcription and final inserted text
✅ Processing latency is <10ms for TextCleaner
✅ All tests pass
✅ Backward compatible with existing history files

## Future Enhancements (Out of Scope for v0)

- v1 LLM refinement with actual API integration
- Settings UI for configuration
- Processing stats/metrics in history menu
- Custom cleaning rules (user-defined regex)
- Language-specific cleaning rules
- A/B testing framework for comparing processors

## Timeline Estimate

- Phase 1 (Core Infrastructure): 2-3 hours
- Phase 2 (Integration): 1-2 hours
- Phase 3 (v1 LLM, optional): 2-3 hours
- Phase 4 (UI, optional): 1-2 hours
- Phase 5 (Testing & Polish): 1-2 hours

**Total for v0 (Phases 1, 2, 5)**: 4-7 hours
**Total for v0 + v1 (All phases)**: 8-12 hours

## Notes

- Start with v0 only (TextCleaner) to validate the architecture
- v1 (LLMRefiner) can be added later without breaking changes
- Keep the pipeline extensible for future processors (e.g., language detection, translation)
- Consider adding telemetry to measure real-world processing times and success rates
