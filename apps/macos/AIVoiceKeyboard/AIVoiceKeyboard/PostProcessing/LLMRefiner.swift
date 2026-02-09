import Foundation

/// LLM-based text refiner that uses an LLM API to improve transcribed text
final class LLMRefiner: PostProcessor {
  private let apiClient: LLMAPIClient
  private let systemPrompt: String
  
  /// Initialize LLM refiner
  /// - Parameters:
  ///   - apiClient: The LLM API client to use
  ///   - systemPrompt: Custom system prompt (optional, uses default if nil)
  init(apiClient: LLMAPIClient, systemPrompt: String? = nil) {
    self.apiClient = apiClient
    self.systemPrompt = systemPrompt ?? Self.defaultSystemPrompt
  }
  
  func process(text: String, timeout: TimeInterval) async throws -> String {
    NSLog("[PostProcessing][LLMRefiner] Starting — input length: %d, timeout: %.1fs", text.count, timeout)
    do {
      let result = try await apiClient.refine(
        text: text,
        systemPrompt: systemPrompt,
        timeout: timeout
      )
      NSLog("[PostProcessing][LLMRefiner] Succeeded — output length: %d", result.count)
      return result
    } catch let error as LLMAPIError {
      // Convert LLMAPIError to PostProcessingError
      switch error {
      case .timeout:
        NSLog("[PostProcessing][LLMRefiner] Failed — timeout")
        throw PostProcessingError.timeout
      case .cancelled:
        NSLog("[PostProcessing][LLMRefiner] Failed — cancelled")
        throw PostProcessingError.cancelled
      default:
        NSLog("[PostProcessing][LLMRefiner] Failed — %@", String(describing: error))
        throw PostProcessingError.processingFailed(underlying: error)
      }
    } catch is CancellationError {
      NSLog("[PostProcessing][LLMRefiner] Failed — CancellationError")
      throw PostProcessingError.cancelled
    } catch {
      NSLog("[PostProcessing][LLMRefiner] Failed — %@", error.localizedDescription)
      throw PostProcessingError.processingFailed(underlying: error)
    }
  }
  
  // MARK: - Default System Prompt
  
  private static let defaultSystemPrompt = """
    You are a text refinement assistant. Your task is to:
    1. Fix obvious transcription errors
    2. Improve grammar and punctuation
    3. Maintain the original meaning and tone
    4. Keep the text concise
    
    Return ONLY the refined text, no explanations.
    """
}
