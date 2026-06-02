import XCTest

@testable import SlackAuthKit

final class SlackTokenProbeTests: XCTestCase {
  func testRequestShape() {
    let request = SlackTokenProbe.makeRequest(
      xoxc: "xoxc-abc", xoxd: "xoxd-enc%2Fok",
      environment: ["SLACK_BASE_URL": "https://example.test/api"])
    XCTAssertEqual(request.url?.absoluteString, "https://example.test/api/auth.test")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer xoxc-abc")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "d=xoxd-enc%2Fok")
    XCTAssertEqual(
      request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
  }

  func testDefaultBaseURL() {
    let request = SlackTokenProbe.makeRequest(xoxc: "x", xoxd: "y", environment: [:])
    XCTAssertEqual(request.url?.absoluteString, "https://slack.com/api/auth.test")
  }

  func testParseSuccess() {
    let json = """
      {"ok":true,"url":"https://acme.slack.com/","team":"Acme","user":"natik",
       "team_id":"T01","user_id":"U01"}
      """
    let result = SlackTokenProbe.parse(Data(json.utf8))
    XCTAssertTrue(result.ok)
    XCTAssertEqual(result.team, "Acme")
    XCTAssertEqual(result.user, "natik")
    XCTAssertEqual(result.teamID, "T01")
    XCTAssertNil(result.error)
  }

  func testParseFailure() {
    let result = SlackTokenProbe.parse(Data(#"{"ok":false,"error":"invalid_auth"}"#.utf8))
    XCTAssertFalse(result.ok)
    XCTAssertEqual(result.error, "invalid_auth")
  }

  func testParseUnparseable() {
    let result = SlackTokenProbe.parse(Data("not json".utf8))
    XCTAssertFalse(result.ok)
    XCTAssertEqual(result.error, "unparseable_response")
  }
}
