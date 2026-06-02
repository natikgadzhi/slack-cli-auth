import XCTest

@testable import SlackAuthKit

final class SlackCaptureTests: XCTestCase {
  func testParsesMultipleWorkspaces() {
    let result: [String: Any] = [
      "ok": true,
      "teams": [
        [
          "id": "T01", "name": "Acme", "domain": "acme", "url": "https://acme.slack.com/",
          "token": "xoxc-aaa",
        ],
        [
          "id": "T02", "name": "Beta", "domain": "beta", "url": "https://beta.slack.com/",
          "token": "xoxc-bbb",
        ],
      ],
    ]
    let workspaces = SlackCapture.parse(result)
    XCTAssertEqual(workspaces?.count, 2)
    XCTAssertEqual(workspaces?[0].teamID, "T01")
    XCTAssertEqual(workspaces?[0].name, "Acme")
    XCTAssertEqual(workspaces?[0].xoxc, "xoxc-aaa")
    XCTAssertEqual(workspaces?[1].xoxc, "xoxc-bbb")
  }

  func testFallsBackToDomainThenIDForName() {
    let result: [String: Any] = [
      "ok": true,
      "teams": [
        ["id": "T01", "name": "", "domain": "acme", "token": "xoxc-aaa"],
        ["id": "T02", "name": "", "domain": "", "token": "xoxc-bbb"],
      ],
    ]
    let workspaces = SlackCapture.parse(result)
    XCTAssertEqual(workspaces?[0].name, "acme")
    XCTAssertEqual(workspaces?[1].name, "T02")
  }

  func testSkipsTeamsWithoutXoxcToken() {
    let result: [String: Any] = [
      "ok": true,
      "teams": [
        ["id": "T01", "name": "Acme", "token": "xoxc-aaa"],
        ["id": "T02", "name": "NoToken", "token": "not-a-token"],
      ],
    ]
    let workspaces = SlackCapture.parse(result)
    XCTAssertEqual(workspaces?.count, 1)
    XCTAssertEqual(workspaces?[0].teamID, "T01")
  }

  func testReturnsNilWhenNotOk() {
    XCTAssertNil(SlackCapture.parse(["ok": false, "teams": []]))
  }

  func testReturnsNilForEmptyOrMalformed() {
    XCTAssertNil(SlackCapture.parse(nil))
    XCTAssertNil(SlackCapture.parse("garbage"))
    XCTAssertNil(SlackCapture.parse(["ok": true, "teams": []]))
  }

  func testReturnsNilWhenTeamMissingID() {
    let result: [String: Any] = [
      "ok": true,
      "teams": [["name": "Acme", "token": "xoxc-aaa"]],
    ]
    XCTAssertNil(SlackCapture.parse(result))
  }

  func testDiagnosticIsSecretFree() {
    let diag = SlackCapture.diagnostic([
      "hasLocalConfig": true, "teamCount": 3,
      "teams": [["token": "xoxc-secret"]],
    ])
    XCTAssertFalse(diag.contains("xoxc-secret"))
    XCTAssertTrue(diag.contains("localConfig=true"))
  }
}
