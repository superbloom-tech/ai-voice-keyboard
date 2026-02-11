import Foundation
import VoiceKeyboardCore

enum STTEngineFactory {
  struct EngineContext {
    let engine: any STTEngine
    let locale: Locale
    let stopTimeoutSeconds: Double
  }

  static func make(config: STTProviderConfiguration) -> EngineContext {
    switch config {
    case .appleSpeech(let cfg):
      let localeIdentifier = cfg.localeIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
      let locale = (localeIdentifier?.isEmpty == false) ? Locale(identifier: localeIdentifier!) : .current
      return EngineContext(
        engine: AppleSpeechSTTEngine(configuration: cfg),
        locale: locale,
        stopTimeoutSeconds: 2.0
      )

    case .whisperLocal(let cfg):
      return EngineContext(
        engine: WhisperCLISTTEngine(configuration: cfg),
        locale: .current,
        stopTimeoutSeconds: max(5.0, cfg.inferenceTimeoutSeconds + 5.0)
      )

    case .openAICompatible(let cfg):
      return EngineContext(
        engine: OpenAICompatibleSTTEngine(configuration: cfg),
        locale: .current,
        stopTimeoutSeconds: max(5.0, cfg.requestTimeoutSeconds + 5.0)
      )

    case .elevenLabsREST(let cfg):
      return EngineContext(
        engine: ElevenLabsRESTSTTEngine(configuration: cfg),
        locale: .current,
        stopTimeoutSeconds: max(5.0, cfg.requestTimeoutSeconds + 5.0)
      )
    }
  }
}
