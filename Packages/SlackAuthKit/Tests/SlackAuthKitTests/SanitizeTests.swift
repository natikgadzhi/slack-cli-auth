import XCTest

@testable import SlackAuthKit

/// Ported from slack-cli's `internal/auth/sanitize_test.go` so behavior stays
/// byte-identical to the CLI.
final class SanitizeTests: XCTestCase {
  func testTokenTrimsWhitespace() {
    XCTAssertEqual(Sanitize.token("  xoxc-abc  "), "xoxc-abc")
    XCTAssertEqual(Sanitize.token("\txoxc-abc\n"), "xoxc-abc")
  }

  func testTokenStripsSurroundingQuotes() {
    XCTAssertEqual(Sanitize.token("\"xoxc-abc\""), "xoxc-abc")
    XCTAssertEqual(Sanitize.token("'xoxc-abc'"), "xoxc-abc")
  }

  func testTokenStripsBearerPrefixCaseInsensitive() {
    XCTAssertEqual(Sanitize.token("Bearer xoxc-abc"), "xoxc-abc")
    XCTAssertEqual(Sanitize.token("bearer xoxc-abc"), "xoxc-abc")
    XCTAssertEqual(Sanitize.token("BEARER xoxc-abc"), "xoxc-abc")
  }

  func testTokenLeavesCleanValueUntouched() {
    XCTAssertEqual(Sanitize.token("xoxc-abc"), "xoxc-abc")
  }

  func testTokenAppliesAllStepsInOrder() {
    XCTAssertEqual(Sanitize.token("  \"Bearer xoxc-abc\"  "), "xoxc-abc")
  }

  func testStripCookieName() {
    var (value, stripped) = Sanitize.stripCookieName("d=xoxd-abc", name: "d")
    XCTAssertEqual(value, "xoxd-abc")
    XCTAssertTrue(stripped)

    (value, stripped) = Sanitize.stripCookieName("D=xoxd-abc", name: "d")
    XCTAssertEqual(value, "xoxd-abc")
    XCTAssertTrue(stripped)

    (value, stripped) = Sanitize.stripCookieName("xoxd-abc", name: "d")
    XCTAssertEqual(value, "xoxd-abc")
    XCTAssertFalse(stripped)
  }

  func testLooksURLEncoded() {
    XCTAssertTrue(Sanitize.looksURLEncoded("xoxd-abc%2Fdef"))
    XCTAssertTrue(Sanitize.looksURLEncoded("a%20b"))
    XCTAssertFalse(Sanitize.looksURLEncoded("xoxd-abc/def"))
    XCTAssertFalse(Sanitize.looksURLEncoded("plain"))
    XCTAssertFalse(Sanitize.looksURLEncoded("%zz"))
  }

  func testNormalizeXoxdLeavesEncodedUntouched() {
    XCTAssertEqual(Sanitize.normalizeXoxd("xoxd-abc%2Fdef"), "xoxd-abc%2Fdef")
  }

  func testNormalizeXoxdEncodesRawSpecials() {
    // Matches Go url.QueryEscape: + / = encoded, space -> +.
    XCTAssertEqual(Sanitize.normalizeXoxd("a+b/c=d"), "a%2Bb%2Fc%3Dd")
    XCTAssertEqual(Sanitize.normalizeXoxd("a b"), "a+b")
  }

  func testNormalizeXoxdLeavesPlainUnchanged() {
    XCTAssertEqual(Sanitize.normalizeXoxd("xoxd-abcDEF123"), "xoxd-abcDEF123")
  }

  func testNormalizeXoxdEmpty() {
    XCTAssertEqual(Sanitize.normalizeXoxd(""), "")
  }

  func testXoxdFullPipeline() {
    XCTAssertEqual(Sanitize.xoxd("  d=xoxd-abc/def  "), "xoxd-abc%2Fdef")
    XCTAssertEqual(Sanitize.xoxd("\"d=xoxd-already%2Fok\""), "xoxd-already%2Fok")
  }

  func testQueryEscapeUnreservedKept() {
    XCTAssertEqual(Sanitize.queryEscape("AZaz09-_.~"), "AZaz09-_.~")
  }
}
