import Foundation

/// OpenAI API client for text refinement
final class OpenAIClient: LLMAPIClient {
  private let apiKey: String
  private let model: String
  private let baseURL: URL
  
  /// Initialize OpenAI client
  /// - Parameters:
  ///   - apiKey: OpenAI API key
  ///   - model: Model to use (e.g., "gpt-4o-mini", "gpt-4o")
  init(apiKey: String, model: String = "gpt-4o-mini") {
    self.apiKey = apiKey
    self.model = model
    self.baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!
  }
  
  func refine(text: String, systemPrompt: String, timeout: TimeInterval) async throws -> String {
    // Build request
    let request = try buildRequest(text: text, systemPrompt: systemPrompt)
    
    // Send request with timeout
    let (data, response) = try await URLSession.shared.data(for: request, timeout: timeout)
    
    // Parse response
    return try parseResponse(data: data, response: response)
  }
  
  // MARK: - Private Methods
  
  private func buildRequest(text: String, systemPrompt: String) throws -> URLRequest {
    var request = URLRequest(url: baseURL)
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
      throw LLMAPIError.invalidResponse
    }
    
    guard (200...299).contains(httpResponse.statusCode) else {
      let errorMessage = try? parseErrorMessage(from: data)
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
