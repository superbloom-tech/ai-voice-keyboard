import Foundation

// MARK: - PostProcessor Protocol

/// Protocol for text post-processors that can be chained together
protocol PostProcessor {
  /// Process transcribed text with optional timeout
  /// - Parameters:
  ///   - text: Raw transcribed text
  ///   - timeout: Maximum processing time
  /// - Returns: Processed text
  /// - Throws: PostProcessingError if processing fails
  func process(text: String, timeout: TimeInterval) async throws -> String
}

// MARK: - Errors

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

// MARK: - Processing Result Types

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

// MARK: - PostProcessingPipeline

/// Composable pipeline that chains multiple post-processors
final class PostProcessingPipeline {
  enum FallbackBehavior {
    case returnOriginal  // If any processor fails, return original text
    case returnLastValid // Return the last successfully processed text
    case throwError      // Propagate the error
  }
  
  private let processors: [PostProcessor]
  private let fallbackBehavior: FallbackBehavior
  
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
          success: true,
          error: nil
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
