import XCTest

@testable import SlackAuthKit

final class RedactionTests: XCTestCase {
  func testScrubsSlackTokens() {
    let xoxc = "xoxc-1234567890-abcdEFGHijklMNOPqrstUVWX"
    let xoxd = "xoxd-AbCd%2F1234567890abcdefghijklmnop"
    XCTAssertFalse(Redaction.scrubValue("token was \(xoxc)").contains(xoxc))
    XCTAssertFalse(Redaction.scrubValue("cookie d=\(xoxd)").contains("xoxd-AbCd"))
  }

  func testScrubsURLs() {
    let scrubbed = Redaction.scrubValue("failed at https://acme.slack.com/api/auth.test")
    XCTAssertFalse(scrubbed.contains("slack.com"))
    XCTAssertTrue(scrubbed.contains("<url>"))
  }

  func testScrubsUsernamePath() {
    let scrubbed = Redaction.scrubValue("at /Users/natikgadzhi/src/file.swift")
    XCTAssertTrue(scrubbed.contains("/Users/<redacted>"))
    XCTAssertFalse(scrubbed.contains("natikgadzhi"))
  }

  func testContainsLeakBackstop() {
    XCTAssertTrue(Redaction.containsLeak("xoxc-1234567890-abcdEFGHijklMNOPqrstUVWX"))
    XCTAssertTrue(Redaction.containsLeak("https://slack.com"))
    XCTAssertTrue(Redaction.containsLeak("/Users/natikgadzhi/x"))
    XCTAssertTrue(Redaction.containsLeak("plain mention of slack.com host"))
  }

  func testCleanTextSurvives() {
    let clean = "The web content process terminated unexpectedly."
    XCTAssertEqual(Redaction.scrubValue(clean), clean)
    XCTAssertFalse(Redaction.containsLeak(clean))
  }

  func testShortIdentifiersSurvive() {
    let frame = "SlackAuthManager.attemptCapture()"
    XCTAssertFalse(Redaction.containsLeak(frame))
  }
}
