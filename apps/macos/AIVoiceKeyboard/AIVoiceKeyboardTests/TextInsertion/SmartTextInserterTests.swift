import XCTest
@testable import AIVoiceKeyboard

@MainActor
final class SmartTextInserterTests: XCTestCase {
  private enum TestError: Error { case boom }

  private final class MockInserter: TextInserter {
    var callCount = 0
    var result: Result<TextInsertionMethod, Error>

    init(result: Result<TextInsertionMethod, Error>) {
      self.result = result
    }

    @discardableResult
    func insert(text: String) throws -> TextInsertionMethod {
      callCount += 1
      return try result.get()
    }
  }

  func testAXSuccessReturnsAXAndDoesNotCallPaste() throws {
    let ax = MockInserter(result: .success(.ax))
    let paste = MockInserter(result: .success(.paste))
    let sut = SmartTextInserter(ax: ax, paste: paste, isAccessibilityEnabled: { true })

    let method = try sut.insert(text: "hello")

    XCTAssertEqual(method, .ax)
    XCTAssertEqual(ax.callCount, 1)
    XCTAssertEqual(paste.callCount, 0)
  }

  func testAXFailureFallsBackToPaste() throws {
    let ax = MockInserter(result: .failure(TestError.boom))
    let paste = MockInserter(result: .success(.pasteClipboardOnly))
    let sut = SmartTextInserter(ax: ax, paste: paste, isAccessibilityEnabled: { true })

    let method = try sut.insert(text: "hello")

    XCTAssertEqual(method, .pasteClipboardOnly)
    XCTAssertEqual(ax.callCount, 1)
    XCTAssertEqual(paste.callCount, 1)
  }

  func testNoAccessibilityGoesDirectlyToPaste() throws {
    let ax = MockInserter(result: .success(.ax))
    let paste = MockInserter(result: .success(.pasteClipboardOnly))
    let sut = SmartTextInserter(ax: ax, paste: paste, isAccessibilityEnabled: { false })

    let method = try sut.insert(text: "hello")

    XCTAssertEqual(method, .pasteClipboardOnly)
    XCTAssertEqual(ax.callCount, 0)
    XCTAssertEqual(paste.callCount, 1)
  }

  func testAXFailureAndPasteFailurePropagatesError() {
    let ax = MockInserter(result: .failure(TestError.boom))
    let paste = MockInserter(result: .failure(TestError.boom))
    let sut = SmartTextInserter(ax: ax, paste: paste, isAccessibilityEnabled: { true })

    XCTAssertThrowsError(try sut.insert(text: "hello"))
    XCTAssertEqual(ax.callCount, 1)
    XCTAssertEqual(paste.callCount, 1)
  }
}
