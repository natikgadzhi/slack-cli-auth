import XCTest

@testable import SlackAuthKit

final class SlackEndpointTests: XCTestCase {
  func testLoginUserAgentLooksLikeDesktopSafari() {
    let ua = SlackEndpoint.loginUserAgent
    // The whole point is that, unlike WKWebView's default, this carries the
    // Version/… and Safari/… tokens Slack's browser sniff requires.
    XCTAssertTrue(ua.hasPrefix("Mozilla/5.0 (Macintosh; Intel Mac OS X"))
    XCTAssertTrue(ua.contains("AppleWebKit/605.1.15 (KHTML, like Gecko)"))
    XCTAssertTrue(ua.contains("Version/"))
    XCTAssertTrue(ua.hasSuffix("Safari/605.1.15"))
  }

  func testIsSlackCookieDomain() {
    XCTAssertTrue(SlackEndpoint.isSlackCookieDomain("slack.com"))
    XCTAssertTrue(SlackEndpoint.isSlackCookieDomain(".slack.com"))
    XCTAssertTrue(SlackEndpoint.isSlackCookieDomain("app.slack.com"))
    XCTAssertFalse(SlackEndpoint.isSlackCookieDomain("notslack.com"))
    XCTAssertFalse(SlackEndpoint.isSlackCookieDomain("slack.com.evil.com"))
  }
}
