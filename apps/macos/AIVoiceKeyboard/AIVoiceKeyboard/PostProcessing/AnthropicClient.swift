import Foundation

/// Anthropic Messages API client for text refinement.
final class AnthropicClient: LLMAPIClient {
  private let apiKey: String
  private let model: String
  private let endpointURL: URL

  private static let defaultBaseURL = URL(string: "https://api.anthropic.com/v1")!
  private static let endpointPath = "/messages"
  private static let anthropicVersionHeaderValue = "2023-06-01"

  /// Initialize Anthropic client
  /// - Parameters:
  ///   - apiKey: Anthropic API key
  ///   - model: Model to use (e.g., "claude-3-5-sonnet-latest")
  ///   - baseURL: Base URL (e.g., "https://api.anthropic.com/v1")
  init(apiKey: String, model: String, baseURL: URL = AnthropicClient.defaultBaseURL) {
    self.apiKey = apiKey
    self.model = model
    self.endpointURL = LLMEndpoint.makeEndpointURL(baseURL: baseURL, endpointPath: Self.endpointPath)
  }

  func refine(text: String, systemPrompt: String, timeout: TimeInterval) async throws -> String {
    NSLog("[PostProcessing][AnthropicClient] Starting refine request - model: %@, endpoint: %@, timeout: %.1fs, text length: %d",
          model, endpointURL.absoluteString, timeout, text.count)
    do {
      let request = try buildRequest(text: text, systemPrompt: systemPrompt)
      NSLog("[PostProcessing][AnthropicClient] Request built - URL: %@", request.url?.absoluteString ?? "nil")

      let (data, response) = try await URLSession.shared.data(for: request, timeout: timeout)
      let result = try parseResponse(data: data, response: response)
      NSLog("[PostProcessing][AnthropicClient] Refine succeeded - result length: %d", result.count)
      return result
    } catch let error as LLMAPIError {
      NSLog("[PostProcessing][AnthropicClient] LLMAPIError: %@", String(describing: error))
      throw error
    } catch is CancellationError {
      NSLog("[PostProcessing][AnthropicClient] Request cancelled")
      throw LLMAPIError.cancelled
    } catch let error as URLError {
      if error.code == .timedOut {
        NSLog("[PostProcessing][AnthropicClient] Request timed out")
        throw LLMAPIError.timeout
      }
      NSLog("[PostProcessing][AnthropicClient] Network error: %@", error.localizedDescription)
      throw LLMAPIError.networkError(underlying: error)
    } catch {
      NSLog("[PostProcessing][AnthropicClient] Unexpected error: %@", error.localizedDescription)
      throw LLMAPIError.invalidResponse
    }
  }

  // MARK: - Private Methods

  private func buildRequest(text: String, systemPrompt: String) throws -> URLRequest {
    var request = URLRequest(url: endpointURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue(Self.anthropicVersionHeaderValue, forHTTPHeaderField: "anthropic-version")

    let body: [String: Any] = [
      "model": model,
      "system": systemPrompt,
      "messages": [
        ["role": "user", "content": text]
      ],
      "temperature": 0.3,
      "max_tokens": 500
    ]

    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    return request
  }

  private func parseResponse(data: Data, response: URLResponse) throws -> String {
    guard let httpResponse = response as? HTTPURLResponse else {
      NSLog("[PostProcessing][AnthropicClient] Response is not HTTPURLResponse")
      throw LLMAPIError.invalidResponse
    }

    NSLog("[PostProcessing][AnthropicClient] HTTP status: %d", httpResponse.statusCode)

    switch httpResponse.statusCode {
    case 200...299:
      break
    case 401, 403:
      NSLog("[PostProcessing][AnthropicClient] Invalid API key (HTTP %d)", httpResponse.statusCode)
      throw LLMAPIError.invalidAPIKey
    default:
      let message = (try? parseErrorMessage(from: data)) ?? "Unknown error"
      NSLog("[PostProcessing][AnthropicClient] API error (HTTP %d): %@", httpResponse.statusCode, message)
      throw LLMAPIError.apiError(statusCode: httpResponse.statusCode, message: message)
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw LLMAPIError.invalidResponse
    }

    // Anthropic Messages response: `content` is an array of blocks like { "type": "text", "text": "..." }
    if let blocks = json["content"] as? [[String: Any]] {
      let texts = blocks.compactMap { block -> String? in
        guard (block["type"] as? String) == "text" else { return nil }
        return block["text"] as? String
      }
      let joined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !joined.isEmpty else { throw LLMAPIError.emptyResponse }
      return joined
    }

    // Fallback for unexpected response shapes.
    throw LLMAPIError.invalidResponse
  }

  private func parseErrorMessage(from data: Data) throws -> String {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return "Unknown error"
    }

    // Common shape:
    // { "type": "error", "error": { "type": "...", "message": "..." } }
    if let error = json["error"] as? [String: Any],
       let message = error["message"] as? String {
      return message
    }

    // Alternate shape:
    // { "message": "..." }
    if let message = json["message"] as? String {
      return message
    }

    return "Unknown error"
  }
}
