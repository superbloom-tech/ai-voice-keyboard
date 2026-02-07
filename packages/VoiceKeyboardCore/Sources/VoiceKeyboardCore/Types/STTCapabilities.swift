import Foundation

public struct STTCapabilities: Codable, Equatable, Sendable {
  public var supportsStreaming: Bool
  public var supportsOnDeviceRecognition: Bool?
  public var supportedLocaleIdentifiers: [String]?

  public init(
    supportsStreaming: Bool,
    supportsOnDeviceRecognition: Bool? = nil,
    supportedLocaleIdentifiers: [String]? = nil
  ) {
    self.supportsStreaming = supportsStreaming
    self.supportsOnDeviceRecognition = supportsOnDeviceRecognition
    self.supportedLocaleIdentifiers = supportedLocaleIdentifiers
  }
}

