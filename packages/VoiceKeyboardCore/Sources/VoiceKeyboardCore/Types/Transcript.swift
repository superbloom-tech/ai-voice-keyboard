public struct Transcript: Codable, Equatable, Sendable {
  public var text: String
  public var isFinal: Bool

  public init(text: String, isFinal: Bool) {
    self.text = text
    self.isFinal = isFinal
  }
}

