//
//  PostProcessingPipelineTests.swift
//  AIVoiceKeyboardTests
//
//  Integration tests for PostProcessingPipeline
//

import XCTest
@testable import AIVoiceKeyboard

final class PostProcessingPipelineTests: XCTestCase {
  
  // MARK: - Single Processor Tests
  
  func testPipelineWithOnlyCleaner() async throws {
    let cleaner = TextCleaner(rules: .standard)
    let pipeline = PostProcessingPipeline(processors: [cleaner])
    
    let result = try await pipeline.process(text: "hello   world", timeout: 1.0)
    
    // TextCleaner should normalize whitespace
    XCTAssertEqual(result.finalText, "hello world")
    XCTAssertEqual(result.steps.count, 1)
    XCTAssertEqual(result.steps[0].processorName, "TextCleaner")
  }
  
  func testPipelineWithOnlyRefiner() async throws {
    let mockClient = MockLLMAPIClient(result: .success("refined text"))
    let refiner = LLMRefiner(apiClient: mockClient)
    let pipeline = PostProcessingPipeline(processors: [refiner])
    
    let result = try await pipeline.process(text: "original text", timeout: 2.0)
    
    XCTAssertEqual(result.finalText, "refined text")
    XCTAssertEqual(result.steps.count, 1)
    XCTAssertEqual(result.steps[0].processorName, "LLMRefiner")
  }
  
  // MARK: - Multiple Processor Tests
  
  func testPipelineWithCleanerAndRefiner() async throws {
    let cleaner = TextCleaner(rules: .standard)
    let mockClient = MockLLMAPIClient(result: .success("refined text"))
    let refiner = LLMRefiner(apiClient: mockClient)
    let pipeline = PostProcessingPipeline(processors: [cleaner, refiner])
    
    let result = try await pipeline.process(text: "hello   world", timeout: 3.0)
    
    // Should apply both processors in order
    XCTAssertEqual(result.finalText, "refined text")
    XCTAssertEqual(result.steps.count, 2)
    XCTAssertEqual(result.steps[0].processorName, "TextCleaner")
    XCTAssertEqual(result.steps[1].processorName, "LLMRefiner")
  }
  
  // MARK: - Error Handling Tests
  
  func testPipelineWithRefinerTimeout() async {
    let cleaner = TextCleaner(rules: .standard)
    let mockClient = MockLLMAPIClient(result: .failure(.timeout))
    let refiner = LLMRefiner(apiClient: mockClient)
    let pipeline = PostProcessingPipeline(
      processors: [cleaner, refiner],
      fallbackBehavior: .throwError
    )
    
    do {
      _ = try await pipeline.process(text: "hello world", timeout: 3.0)
      XCTFail("Should throw timeout error")
    } catch let error as PostProcessingError {
      if case .timeout = error {
        // Success - timeout should propagate
      } else {
        XCTFail("Should throw PostProcessingError.timeout, got \(error)")
      }
    } catch {
      XCTFail("Should throw PostProcessingError, got \(error)")
    }
  }
  
  func testPipelineWithRefinerCancelled() async {
    let cleaner = TextCleaner(rules: .standard)
    let mockClient = MockLLMAPIClient(result: .failure(.cancelled))
    let refiner = LLMRefiner(apiClient: mockClient)
    let pipeline = PostProcessingPipeline(
      processors: [cleaner, refiner],
      fallbackBehavior: .throwError
    )
    
    do {
      _ = try await pipeline.process(text: "hello world", timeout: 3.0)
      XCTFail("Should throw cancelled error")
    } catch let error as PostProcessingError {
      if case .cancelled = error {
        // Success - cancellation should propagate
      } else {
        XCTFail("Should throw PostProcessingError.cancelled, got \(error)")
      }
    } catch {
      XCTFail("Should throw PostProcessingError, got \(error)")
    }
  }
  
  func testPipelineWithRefinerError() async {
    let cleaner = TextCleaner(rules: .standard)
    let mockClient = MockLLMAPIClient(result: .failure(.invalidResponse))
    let refiner = LLMRefiner(apiClient: mockClient)
    let pipeline = PostProcessingPipeline(
      processors: [cleaner, refiner],
      fallbackBehavior: .throwError
    )
    
    do {
      _ = try await pipeline.process(text: "hello world", timeout: 3.0)
      XCTFail("Should throw processing failed error")
    } catch let error as PostProcessingError {
      if case .processingFailed = error {
        // Success - error should propagate
      } else {
        XCTFail("Should throw PostProcessingError.processingFailed, got \(error)")
      }
    } catch {
      XCTFail("Should throw PostProcessingError, got \(error)")
    }
  }
  
  // MARK: - Empty Pipeline Tests
  
  func testEmptyPipeline() async throws {
    let pipeline = PostProcessingPipeline(processors: [])
    
    let result = try await pipeline.process(text: "hello world", timeout: 1.0)
    
    // Empty pipeline should return original text
    XCTAssertEqual(result.finalText, "hello world")
    XCTAssertEqual(result.steps.count, 0)
  }
  
  // MARK: - Processing Steps Tests
  
  func testProcessingStepsRecorded() async throws {
    let cleaner = TextCleaner(rules: .standard)
    let mockClient = MockLLMAPIClient(result: .success("refined text"))
    let refiner = LLMRefiner(apiClient: mockClient)
    let pipeline = PostProcessingPipeline(processors: [cleaner, refiner])
    
    let result = try await pipeline.process(text: "hello   world", timeout: 3.0)
    
    // Verify processing steps are recorded
    XCTAssertEqual(result.steps.count, 2)
    
    // First step: TextCleaner
    XCTAssertEqual(result.steps[0].processorName, "TextCleaner")
    XCTAssertEqual(result.steps[0].input, "hello   world")
    XCTAssertEqual(result.steps[0].output, "hello world")
    XCTAssertNil(result.steps[0].error)
    
    // Second step: LLMRefiner
    XCTAssertEqual(result.steps[1].processorName, "LLMRefiner")
    XCTAssertEqual(result.steps[1].input, "hello world")
    XCTAssertEqual(result.steps[1].output, "refined text")
    XCTAssertNil(result.steps[1].error)
  }
}
