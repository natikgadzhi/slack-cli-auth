import XCTest

@testable import SlackAuthKit

final class SlackSecretStoreTests: XCTestCase {
  func testInMemoryRoundTrip() {
    let store = InMemorySlackSecretStore()
    XCTAssertNil(store.read())

    let tokens = SlackTokens(xoxc: "xoxc-abc", xoxd: "xoxd-enc%2Fok")
    XCTAssertTrue(store.write(tokens))

    let read = store.read()
    XCTAssertEqual(read?.xoxc, "xoxc-abc")
    XCTAssertEqual(read?.xoxd, "xoxd-enc%2Fok")
  }

  func testInMemoryClear() {
    let store = InMemorySlackSecretStore()
    store.write(SlackTokens(xoxc: "a", xoxd: "b"))
    store.clear()
    XCTAssertNil(store.read())
  }

  func testInMemoryOverwrite() {
    let store = InMemorySlackSecretStore()
    store.write(SlackTokens(xoxc: "old-c", xoxd: "old-d"))
    store.write(SlackTokens(xoxc: "new-c", xoxd: "new-d"))
    XCTAssertEqual(store.read()?.xoxc, "new-c")
    XCTAssertEqual(store.read()?.xoxd, "new-d")
  }
}
