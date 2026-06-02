import XCTest

@testable import SlackAuthKit

final class KeychainNamesTests: XCTestCase {
  func testAccountPrefersExplicitEnvOverride() {
    let account = KeychainNames.account(
      environment: ["SLACK_KEYCHAIN_ACCOUNT": "override"], loginName: "login")
    XCTAssertEqual(account, "override")
  }

  func testAccountFallsBackToLoginName() {
    let account = KeychainNames.account(environment: [:], loginName: "login")
    XCTAssertEqual(account, "login")
  }

  func testAccountFallsBackToUserEnv() {
    let account = KeychainNames.account(environment: ["USER": "userenv"], loginName: "")
    XCTAssertEqual(account, "userenv")
  }

  func testAccountFinalFallbackIsSlackCli() {
    XCTAssertEqual(KeychainNames.account(environment: [:], loginName: ""), "slack-cli")
  }

  func testServiceDefaults() {
    XCTAssertEqual(KeychainNames.xoxcService(environment: [:]), "slack-xoxc-token")
    XCTAssertEqual(KeychainNames.xoxdService(environment: [:]), "slack-xoxd-token")
  }

  func testServiceOverrides() {
    XCTAssertEqual(
      KeychainNames.xoxcService(environment: ["SLACK_XOXC_SERVICE": "c"]), "c")
    XCTAssertEqual(
      KeychainNames.xoxdService(environment: ["SLACK_XOXD_SERVICE": "d"]), "d")
  }
}
