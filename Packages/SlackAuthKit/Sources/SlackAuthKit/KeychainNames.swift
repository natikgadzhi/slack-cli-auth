import Foundation

/// Keychain coordinates that must match slack-cli's `internal/config/config.go`
/// exactly, so the items this app writes are the ones the CLI reads. Service
/// names and the account name honor the same environment overrides.
public enum KeychainNames {
  /// `kSecAttrAccount` for both items. Resolution order (first non-empty wins),
  /// ported from `config.KeychainAccount`:
  ///   1. `$SLACK_KEYCHAIN_ACCOUNT`
  ///   2. the current login name (`NSUserName()`, == os/user.Current().Username)
  ///   3. `$USER`
  ///   4. the literal `"slack-cli"` (guarantees non-empty)
  ///
  /// `environment` is injectable so the resolution order is unit-testable without
  /// touching the process environment.
  public static func account(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    loginName: String = NSUserName()
  ) -> String {
    if let v = environment["SLACK_KEYCHAIN_ACCOUNT"], !v.isEmpty { return v }
    if !loginName.isEmpty { return loginName }
    if let v = environment["USER"], !v.isEmpty { return v }
    return "slack-cli"
  }

  /// `kSecAttrService` for the `xoxc` token. Override: `$SLACK_XOXC_SERVICE`.
  public static func xoxcService(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> String {
    if let v = environment["SLACK_XOXC_SERVICE"], !v.isEmpty { return v }
    return "slack-xoxc-token"
  }

  /// `kSecAttrService` for the `xoxd` cookie. Override: `$SLACK_XOXD_SERVICE`.
  public static func xoxdService(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> String {
    if let v = environment["SLACK_XOXD_SERVICE"], !v.isEmpty { return v }
    return "slack-xoxd-token"
  }
}
