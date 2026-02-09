import Foundation
import Security

/// Manager for securely storing and retrieving sensitive data using macOS Keychain
final class KeychainManager {
  enum KeychainError: LocalizedError {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case invalidData
    
    var errorDescription: String? {
      switch self {
      case .itemNotFound:
        return "Keychain item not found"
      case .duplicateItem:
        return "Keychain item already exists"
      case .unexpectedStatus(let status):
        return "Keychain operation failed with status: \(status)"
      case .invalidData:
        return "Invalid data format"
      }
    }
  }
  
  /// Save a string value to Keychain
  /// - Parameters:
  ///   - key: The key to identify the item
  ///   - value: The string value to store
  ///   - service: The service name (used to group related items)
  /// - Throws: KeychainError if the operation fails
  static func save(key: String, value: String, service: String) throws {
    guard let data = value.data(using: .utf8) else {
      throw KeychainError.invalidData
    }
    
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
    ]
    
    // Try to add first
    var status = SecItemAdd(query as CFDictionary, nil)
    
    if status == errSecDuplicateItem {
      // Item exists, update it
      let updateQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: key
      ]
      
      let updateAttributes: [String: Any] = [
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
      ]
      
      status = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
    }
    
    guard status == errSecSuccess else {
      throw KeychainError.unexpectedStatus(status)
    }
  }
  
  /// Load a string value from Keychain
  /// - Parameters:
  ///   - key: The key to identify the item
  ///   - service: The service name
  /// - Returns: The stored string value, or nil if not found
  /// - Throws: KeychainError if the operation fails (but not for itemNotFound)
  static func load(key: String, service: String) throws -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    
    guard status == errSecSuccess else {
      if status == errSecItemNotFound {
        return nil
      }
      throw KeychainError.unexpectedStatus(status)
    }
    
    guard let data = result as? Data,
          let string = String(data: data, encoding: .utf8) else {
      throw KeychainError.invalidData
    }
    
    return string
  }
  
  /// Delete a value from Keychain
  /// - Parameters:
  ///   - key: The key to identify the item
  ///   - service: The service name
  /// - Throws: KeychainError if the operation fails
  static func delete(key: String, service: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key
    ]
    
    let status = SecItemDelete(query as CFDictionary)
    
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.unexpectedStatus(status)
    }
  }
  
  /// Check if a key exists in Keychain
  /// - Parameters:
  ///   - key: The key to check
  ///   - service: The service name
  /// - Returns: true if the key exists, false otherwise
  static func exists(key: String, service: String) -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: false
    ]
    
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    return status == errSecSuccess
  }
}
