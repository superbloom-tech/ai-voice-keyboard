import XCTest
@testable import VoiceKeyboardCore

final class DisfluencyCleanerTests: XCTestCase {
  func testEnglishFillerRemoval() throws {
    let cleaner = DisfluencyCleaner()
    let input = "um I think uh this is good"
    let output = cleaner.clean(input, languageHint: .en)
    XCTAssertEqual(output, "I think this is good")
  }

  func testChineseLeadingFillerRemoval() throws {
    let cleaner = DisfluencyCleaner()
    let input = "嗯 我觉得这个可以"
    let output = cleaner.clean(input, languageHint: .zh)
    XCTAssertEqual(output, "我觉得这个可以")
  }

  func testWordRepetitionCompressionEnglish() throws {
    let cleaner = DisfluencyCleaner()
    let input = "I I I think this works"
    let output = cleaner.clean(input, languageHint: .en)
    XCTAssertEqual(output, "I think this works")
  }

  func testCharacterRepetitionCompressionChinesePronounOnly() throws {
    let cleaner = DisfluencyCleaner()
    let input = "我我觉得可以"
    let output = cleaner.clean(input, languageHint: .zh)
    XCTAssertEqual(output, "我觉得可以")
  }

  func testDoesNotOverCleanCommonReduplication() throws {
    let cleaner = DisfluencyCleaner()
    let input = "看看这个"
    let output = cleaner.clean(input, languageHint: .zh)
    XCTAssertEqual(output, "看看这个")
  }
}

