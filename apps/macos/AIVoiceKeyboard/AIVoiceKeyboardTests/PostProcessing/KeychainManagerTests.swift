//
//  KeychainManagerTests.swift
//  AIVoiceKeyboardTests
//
//  Unit tests for KeychainManager
//

import XCTest
@testable import AIVoiceKeyboard

final class KeychainManagerTests: XCTestCase {
  
  let testService = "tech.superbloom.aivoicekeyboard.test"
  let testKey = "test-key"
  let testValue = "test-value"
  
  override func tearDown() {
    super.tearDown()
    // Clean up test data
    try? KeychainManager.delete(key: testKey, service: testService)
  }
  
  // MARK: - Save Tests
  
  func testSaveNewItem() throws {
    // Save a new item
    try KeychainManager.save(key: testKey, value: testValue, service: testService)
    
    // Verify it was saved
    let retrieved = try KeychainManager.load(key: testKey, service: testService)
    XCTAssertEqual(retrieved, testValue)
  }
  
  func testSaveUpdateExistingItem() throws {
    // Save initial value
    try KeychainManager.save(key: testKey, value: "initial", service: testService)
    
    // Update with new value
    try KeychainManager.save(key: testKey, value: testValue, service: testService)
    
    // Verify it was updated
    let retrieved = try KeychainManager.load(key: testKey, service: testService)
    XCTAssertEqual(retrieved, testValue)
  }
  
  // MARK: - Load Tests
  
  func testLoadExistingItem() throws {
    // Save an item
    try KeychainManager.save(key: testKey, value: testValue, service: testService)
    
    // Load it
    let retrieved = try KeychainManager.load(key: testKey, service: testService)
    XCTAssertEqual(retrieved, testValue)
  }
  
  func testLoadNonExistentItem() throws {
    // Try to load an item that doesn't exist
    let retrieved = try KeychainManager.load(key: "non-existent", service: testService)
    XCTAssertNil(retrieved)
  }
  
  // MARK: - Delete Tests
  
  func testDeleteExistingItem() throws {
    // Save an item
    try KeychainManager.save(key: testKey, value: testValue, service: testService)
    
    // Delete it
    try KeychainManager.delete(key: testKey, service: testService)
    
    // Verify it was deleted
    let retrieved = try KeychainManager.load(key: testKey, service: testService)
    XCTAssertNil(retrieved)
  }
  
  func testDeleteNonExistentItem() throws {
    // Deleting a non-existent item should not throw
    try KeychainManager.delete(key: "non-existent", service: testService)
  }
  
  // MARK: - Exists Tests
  
  func testExistsForExistingItem() throws {
    // Save an item
    try KeychainManager.save(key: testKey, value: testValue, service: testService)
    
    // Check if it exists
    let exists = try KeychainManager.exists(key: testKey, service: testService)
    XCTAssertTrue(exists)
  }
  
  func testExistsForNonExistentItem() throws {
    // Check if a non-existent item exists
    let exists = try KeychainManager.exists(key: "non-existent", service: testService)
    XCTAssertFalse(exists)
  }
  
  // MARK: - Edge Cases
  
  func testSaveEmptyString() throws {
    // Save an empty string
    try KeychainManager.save(key: testKey, value: "", service: testService)
    
    // Verify it was saved
    let retrieved = try KeychainManager.load(key: testKey, service: testService)
    XCTAssertEqual(retrieved, "")
  }
  
  func testSaveUnicodeString() throws {
    let unicodeValue = "Hello 世界 🌍"
    
    // Save a Unicode string
    try KeychainManager.save(key: testKey, value: unicodeValue, service: testService)
    
    // Verify it was saved correctly
    let retrieved = try KeychainManager.load(key: testKey, service: testService)
    XCTAssertEqual(retrieved, unicodeValue)
  }
  
  func testSaveLongString() throws {
    let longValue = String(repeating: "a", count: 10000)
    
    // Save a long string
    try KeychainManager.save(key: testKey, value: longValue, service: testService)
    
    // Verify it was saved correctly
    let retrieved = try KeychainManager.load(key: testKey, service: testService)
    XCTAssertEqual(retrieved, longValue)
  }
}
