import XCTest

@testable import SlackAuthKit

final class KeychainNamesTests: XCTestCase {
  func testServiceNamesMatchSlackCliDefaults() {
    XCTAssertEqual(KeychainNames.xoxcService, "slack-xoxc-token")
    XCTAssertEqual(KeychainNames.xoxdService, "slack-xoxd-token")
  }

  func testAccountUsesLoginName() {
    XCTAssertEqual(KeychainNames.account(loginName: "natikgadzhi"), "natikgadzhi")
  }

  func testAccountFallsBackWhenLoginNameEmpty() {
    XCTAssertEqual(KeychainNames.account(loginName: ""), "slack-cli")
  }
}
