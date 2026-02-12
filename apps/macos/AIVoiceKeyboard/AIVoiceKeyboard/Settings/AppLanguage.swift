import Foundation

// MARK: - Language override

enum AppLanguage: String, CaseIterable, Identifiable {
  case system = "system"
  case en = "en"
  case zhHans = "zh-Hans"
  case zhHant = "zh-Hant"

  static let preferenceKey = "avkb.language.preference"
  private static let systemAppleLanguagesBackupKey = "avkb.language.systemAppleLanguagesBackup"

  var id: String { rawValue }

  private var appleLanguageCode: String? {
    self == .system ? nil : rawValue
  }

  static func load() -> AppLanguage {
    let raw = UserDefaults.standard.string(forKey: preferenceKey) ?? AppLanguage.system.rawValue
    return AppLanguage(rawValue: raw) ?? .system
  }

  static func applySavedPreference() {
    applyToAppleLanguages(load())
  }

  static func applyToAppleLanguages(_ language: AppLanguage) {
    // `AppleLanguages` affects `Bundle.main.preferredLocalizations`.
    let defaults = UserDefaults.standard
    let appleLanguagesKey = "AppleLanguages"

    if let code = language.appleLanguageCode {
      // Preserve the "system-determined" app language (including per-app language override in
      // macOS System Settings) so selecting `.system` can restore it.
      if defaults.object(forKey: systemAppleLanguagesBackupKey) == nil {
        let existing = defaults.stringArray(forKey: appleLanguagesKey) ?? []
        defaults.set(existing, forKey: systemAppleLanguagesBackupKey)
      }
      defaults.set([code], forKey: appleLanguagesKey)
      return
    }

    // `.system`: restore previous AppleLanguages value only if we ever overrode it.
    guard let backup = defaults.array(forKey: systemAppleLanguagesBackupKey) as? [String] else {
      return
    }
    defer { defaults.removeObject(forKey: systemAppleLanguagesBackupKey) }

    if backup.isEmpty {
      defaults.removeObject(forKey: appleLanguagesKey)
    } else {
      defaults.set(backup, forKey: appleLanguagesKey)
    }
  }
}

