import Foundation

/// OpenAI API client for text refinement
final class OpenAIClient: LLMAPIClient {
  private let apiKey: String
  private let model: String
  private let endpointURL: URL
  
  private static let defaultBaseURL = URL(string: "https://api.openai.com/v1")!
  private static let endpointPath = "/chat/completions"
  
  /// Initialize OpenAI client
  /// - Parameters:
  ///   - apiKey: OpenAI API key
  ///   - model: Model to use (e.g., "gpt-4o-mini", "gpt-4o")
  ///   - baseURL: Base URL (e.g., "https://api.openai.com/v1", "https://openrouter.ai/api/v1")
  init(apiKey: String, model: String = "gpt-4o-mini", baseURL: URL = OpenAIClient.defaultBaseURL) {
    self.apiKey = apiKey
    self.model = model
    self.endpointURL = LLMEndpoint.makeEndpointURL(baseURL: baseURL, endpointPath: Self.endpointPath)
  }
  
  func refine(text: String, systemPrompt: String, timeout: TimeInterval) async throws -> String {
    NSLog("[PostProcessing][OpenAIClient] Starting refine request — model: %@, endpoint: %@, timeout: %.1fs, text length: %d",
          model, endpointURL.absoluteString, timeout, text.count)
    do {
      // Build request
      let request = try buildRequest(text: text, systemPrompt: systemPrompt)
      NSLog("[PostProcessing][OpenAIClient] Request built — URL: %@", request.url?.absoluteString ?? "nil")
      
      // Send request with timeout
      let (data, response) = try await URLSession.shared.data(for: request, timeout: timeout)
      
      // Parse response
      let result = try parseResponse(data: data, response: response)
      NSLog("[PostProcessing][OpenAIClient] Refine succeeded — result length: %d", result.count)
      return result
    } catch let error as LLMAPIError {
      NSLog("[PostProcessing][OpenAIClient] LLMAPIError: %@", String(describing: error))
      throw error
    } catch is CancellationError {
      NSLog("[PostProcessing][OpenAIClient] Request cancelled")
      throw LLMAPIError.cancelled
    } catch let error as URLError {
      if error.code == .timedOut {
        NSLog("[PostProcessing][OpenAIClient] Request timed out")
        throw LLMAPIError.timeout
      }
      NSLog("[PostProcessing][OpenAIClient] Network error: %@", error.localizedDescription)
      throw LLMAPIError.networkError(underlying: error)
    } catch {
      NSLog("[PostProcessing][OpenAIClient] Unexpected error: %@", error.localizedDescription)
      throw LLMAPIError.invalidResponse
    }
  }
  
  // MARK: - Private Methods
  
  private func buildRequest(text: String, systemPrompt: String) throws -> URLRequest {
    var request = URLRequest(url: endpointURL)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let body: [String: Any] = [
      "model": model,
      "messages": [
        ["role": "system", "content": systemPrompt],
        ["role": "user", "content": text]
      ],
      "temperature": 0.3,
      "max_tokens": 500
    ]
    
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    
    return request
  }
  
  private func parseResponse(data: Data, response: URLResponse) throws -> String {
    // Check HTTP status code
    guard let httpResponse = response as? HTTPURLResponse else {
      NSLog("[PostProcessing][OpenAIClient] Response is not HTTPURLResponse")
      throw LLMAPIError.invalidResponse
    }
    
    NSLog("[PostProcessing][OpenAIClient] HTTP status: %d", httpResponse.statusCode)
    
    // Map specific status codes
    switch httpResponse.statusCode {
    case 200...299:
      // Success, continue parsing
      break
    case 401, 403:
      NSLog("[PostProcessing][OpenAIClient] Invalid API key (HTTP %d)", httpResponse.statusCode)
      throw LLMAPIError.invalidAPIKey
    default:
      // Other API errors
      let errorMessage = try? parseErrorMessage(from: data)
      NSLog("[PostProcessing][OpenAIClient] API error (HTTP %d): %@", httpResponse.statusCode, errorMessage ?? "Unknown error")
      throw LLMAPIError.apiError(
        statusCode: httpResponse.statusCode,
        message: errorMessage ?? "Unknown error"
      )
    }
    
    // Parse JSON response
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = json["choices"] as? [[String: Any]],
          let firstChoice = choices.first,
          let message = firstChoice["message"] as? [String: Any],
          let content = message["content"] as? String else {
      throw LLMAPIError.invalidResponse
    }
    
    guard !content.isEmpty else {
      throw LLMAPIError.emptyResponse
    }
    
    return content.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  
  private func parseErrorMessage(from data: Data) throws -> String {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let error = json["error"] as? [String: Any],
          let message = error["message"] as? String else {
      return "Unknown error"
    }
    return message
  }
}
