import Foundation

// MARK: - LLMAPIClient Protocol

/// Protocol for LLM API clients that can refine text
protocol LLMAPIClient {
  /// Refine text using LLM
  /// - Parameters:
  ///   - text: The text to refine
  ///   - systemPrompt: The system prompt to guide the refinement
  ///   - timeout: Maximum time to wait for the response
  /// - Returns: The refined text
  /// - Throws: LLMAPIError if the operation fails
  func refine(text: String, systemPrompt: String, timeout: TimeInterval) async throws -> String
}

// MARK: - LLMAPIError

enum LLMAPIError: LocalizedError {
  case invalidAPIKey
  case networkError(underlying: Error)
  case apiError(statusCode: Int, message: String)
  case timeout
  case cancelled
  case invalidResponse
  case emptyResponse
  
  var errorDescription: String? {
    switch self {
    case .invalidAPIKey:
      return "Invalid API key"
    case .networkError(let error):
      return "Network error: \(error.localizedDescription)"
    case .apiError(let statusCode, let message):
      return "API error (\(statusCode)): \(message)"
    case .timeout:
      return "Request timed out"
    case .cancelled:
      return "Request was cancelled"
    case .invalidResponse:
      return "Invalid response from API"
    case .emptyResponse:
      return "Empty response from API"
    }
  }
}

// MARK: - URLSession Extension for Timeout

extension URLSession {
  /// Perform a data task with timeout
  func data(for request: URLRequest, timeout: TimeInterval) async throws -> (Data, URLResponse) {
    // Validate timeout
    guard timeout > 0 else {
      throw LLMAPIError.timeout
    }
    
    return try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
      // Add the actual request task
      group.addTask {
        do {
          return try await self.data(for: request)
        } catch is CancellationError {
          throw LLMAPIError.cancelled
        } catch {
          throw error
        }
      }
      
      // Add the timeout task
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        throw LLMAPIError.timeout
      }
      
      // Wait for the first task to complete
      guard let result = try await group.next() else {
        throw LLMAPIError.cancelled
      }
      
      // Cancel the other task
      group.cancelAll()
      
      return result
    }
  }
}
