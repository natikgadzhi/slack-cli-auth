import Foundation
import Security

/// The pair of tokens slack-cli needs for an authenticated session.
public struct SlackTokens: Sendable, Equatable {
  public let xoxc: String
  public let xoxd: String
  public init(xoxc: String, xoxd: String) {
    self.xoxc = xoxc
    self.xoxd = xoxd
  }
}

/// Where the Slack tokens live. One protocol, two impls: Keychain for real use,
/// in-memory for tests.
public protocol SlackSecretStoring: Sendable {
  func read() -> SlackTokens?
  /// Returns whether BOTH items actually persisted, so the caller doesn't report
  /// a session it couldn't fully store.
  @discardableResult func write(_ tokens: SlackTokens) -> Bool
  func clear()
}

/// Test double. Holds tokens in process memory only — never for production use.
public final class InMemorySlackSecretStore: SlackSecretStoring, @unchecked Sendable {
  private var stored: SlackTokens?
  public init() {}
  public func read() -> SlackTokens? { stored }
  @discardableResult public func write(_ tokens: SlackTokens) -> Bool {
    stored = tokens
    return true
  }
  public func clear() { stored = nil }
}

/// Keychain-backed store. Writes two **generic-password** items — one per token —
/// each holding the plain UTF-8 token string, matching `zalando/go-keyring` (what
/// slack-cli uses). The items are keyed by `service` + `account`; `write` deletes
/// any prior item first to avoid duplicates and stale accessibility.
public final class KeychainSlackSecretStore: SlackSecretStoring, @unchecked Sendable {
  private let xoxcService: String
  private let xoxdService: String
  private let account: String

  public init(
    xoxcService: String = KeychainNames.xoxcService,
    xoxdService: String = KeychainNames.xoxdService,
    account: String = KeychainNames.account()
  ) {
    self.xoxcService = xoxcService
    self.xoxdService = xoxdService
    self.account = account
  }

  public func read() -> SlackTokens? {
    guard let xoxc = readItem(service: xoxcService),
      let xoxd = readItem(service: xoxdService)
    else {
      return nil
    }
    return SlackTokens(xoxc: xoxc, xoxd: xoxd)
  }

  @discardableResult public func write(_ tokens: SlackTokens) -> Bool {
    let okXoxc = writeItem(service: xoxcService, value: tokens.xoxc)
    let okXoxd = writeItem(service: xoxdService, value: tokens.xoxd)
    return okXoxc && okXoxd
  }

  public func clear() {
    SecItemDelete(baseQuery(service: xoxcService) as CFDictionary)
    SecItemDelete(baseQuery(service: xoxdService) as CFDictionary)
  }

  private func readItem(service: String) -> String? {
    var query = baseQuery(service: service)
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data,
      let value = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    return value
  }

  private func writeItem(service: String, value: String) -> Bool {
    guard let data = value.data(using: .utf8) else { return false }
    let base = baseQuery(service: service)

    // Try to add fresh. If an item already exists (e.g. slack-cli wrote one and
    // its ACL won't let us delete it), fall back to updating that item's value in
    // place. Update only touches the data, so it works even when delete/add would
    // collide. We still try a delete first to clear any stale accessibility, but
    // ignore its result — the add/update below is what matters.
    SecItemDelete(base as CFDictionary)

    var attributes = base
    attributes[kSecValueData] = data
    // Match go-keyring's accessibility (AccessibleWhenUnlocked): readable only
    // while the Mac is unlocked. These are bearer credentials.
    attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked

    var status = SecItemAdd(attributes as CFDictionary, nil)
    if status == errSecDuplicateItem {
      status = SecItemUpdate(base as CFDictionary, [kSecValueData: data] as CFDictionary)
    }

    #if DEBUG
      if status != errSecSuccess {
        WebDebugLog.write(
          "[keychain] write \(service) failed: OSStatus=\(status) "
            + "(\(SecCopyErrorMessageString(status, nil) as String? ?? "?"))")
      } else {
        WebDebugLog.write("[keychain] write \(service): ok")
      }
    #endif

    return status == errSecSuccess
  }

  private func baseQuery(service: String) -> [CFString: Any] {
    [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
    ]
  }
}
