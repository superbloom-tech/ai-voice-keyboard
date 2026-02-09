//
//  LLMRefinerTests.swift
//  AIVoiceKeyboardTests
//
//  Unit tests for LLMRefiner
//

import XCTest
@testable import AIVoiceKeyboard

final class LLMRefinerTests: XCTestCase {
  
  // MARK: - Success Cases
  
  func testRefineSuccess() async throws {
    let mockClient = MockLLMAPIClient(result: .success("refined text"))
    let refiner = LLMRefiner(apiClient: mockClient)
    
    let result = try await refiner.process(text: "original text", timeout: 2.0)
    
    XCTAssertEqual(result, "refined text")
  }
  
  // MARK: - Error Cases
  
  func testRefineTimeout() async {
    let mockClient = MockLLMAPIClient(result: .failure(.timeout))
    let refiner = LLMRefiner(apiClient: mockClient)
    
    do {
      _ = try await refiner.process(text: "original text", timeout: 2.0)
      XCTFail("Should throw timeout error")
    } catch let error as PostProcessingError {
      if case .timeout = error {
        // Success - correct error type
      } else {
        XCTFail("Should throw PostProcessingError.timeout, got \(error)")
      }
    } catch {
      XCTFail("Should throw PostProcessingError, got \(error)")
    }
  }
  
  func testRefineCancelled() async {
    let mockClient = MockLLMAPIClient(result: .failure(.cancelled))
    let refiner = LLMRefiner(apiClient: mockClient)
    
    do {
      _ = try await refiner.process(text: "original text", timeout: 2.0)
      XCTFail("Should throw cancelled error")
    } catch let error as PostProcessingError {
      if case .cancelled = error {
        // Success - correct error type
      } else {
        XCTFail("Should throw PostProcessingError.cancelled, got \(error)")
      }
    } catch {
      XCTFail("Should throw PostProcessingError, got \(error)")
    }
  }
  
  func testRefineInvalidAPIKey() async {
    let mockClient = MockLLMAPIClient(result: .failure(.invalidAPIKey))
    let refiner = LLMRefiner(apiClient: mockClient)
    
    do {
      _ = try await refiner.process(text: "original text", timeout: 2.0)
      XCTFail("Should throw processing failed error")
    } catch let error as PostProcessingError {
      if case .processingFailed = error {
        // Success - invalid API key should be wrapped as processingFailed
      } else {
        XCTFail("Should throw PostProcessingError.processingFailed, got \(error)")
      }
    } catch {
      XCTFail("Should throw PostProcessingError, got \(error)")
    }
  }
  
  func testRefineNetworkError() async {
    let urlError = URLError(.notConnectedToInternet)
    let mockClient = MockLLMAPIClient(result: .failure(.networkError(underlying: urlError)))
    let refiner = LLMRefiner(apiClient: mockClient)
    
    do {
      _ = try await refiner.process(text: "original text", timeout: 2.0)
      XCTFail("Should throw processing failed error")
    } catch let error as PostProcessingError {
      if case .processingFailed = error {
        // Success - network error should be wrapped as processingFailed
      } else {
        XCTFail("Should throw PostProcessingError.processingFailed, got \(error)")
      }
    } catch {
      XCTFail("Should throw PostProcessingError, got \(error)")
    }
  }
  
  func testRefineInvalidResponse() async {
    let mockClient = MockLLMAPIClient(result: .failure(.invalidResponse))
    let refiner = LLMRefiner(apiClient: mockClient)
    
    do {
      _ = try await refiner.process(text: "original text", timeout: 2.0)
      XCTFail("Should throw processing failed error")
    } catch let error as PostProcessingError {
      if case .processingFailed = error {
        // Success - invalid response should be wrapped as processingFailed
      } else {
        XCTFail("Should throw PostProcessingError.processingFailed, got \(error)")
      }
    } catch {
      XCTFail("Should throw PostProcessingError, got \(error)")
    }
  }
}
