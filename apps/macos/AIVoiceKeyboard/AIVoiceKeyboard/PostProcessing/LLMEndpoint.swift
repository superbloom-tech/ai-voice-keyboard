import Foundation

/// Utilities for constructing provider endpoints from a user-provided base URL.
enum LLMEndpoint {
  /// Returns `baseURL` with `endpointPath` appended, unless `baseURL` already ends with `endpointPath`.
  ///
  /// This is intentionally tolerant of extra/missing `/` in `baseURL`.
  static func makeEndpointURL(baseURL: URL, endpointPath: String) -> URL {
    let endpointComponents = endpointPath
      .split(separator: "/")
      .map(String.init)
      .filter { !$0.isEmpty }

    guard !endpointComponents.isEmpty else { return baseURL }

    let baseComponents = baseURL.path
      .split(separator: "/")
      .map(String.init)
      .filter { !$0.isEmpty }

    if baseComponents.suffix(endpointComponents.count) == endpointComponents {
      return baseURL
    }

    var url = baseURL
    for component in endpointComponents {
      url = url.appendingPathComponent(component)
    }
    return url
  }
}

