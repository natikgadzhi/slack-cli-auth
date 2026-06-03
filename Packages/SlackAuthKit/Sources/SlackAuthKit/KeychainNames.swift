import Foundation

/// Keychain coordinates that must match slack-cli's defaults so the items this
/// app writes are the ones the CLI reads.
///
/// slack-cli (a CLI) lets you override the service/account names via environment
/// variables. This is a GUI app launched from Finder/Dock, which inherits none of
/// your shell's environment — so those overrides could never reach us, and if you
/// did set them for slack-cli we'd mismatch no matter what. We therefore match
/// slack-cli's *default* resolution, which is what every normal install uses.
public enum KeychainNames {
  /// `kSecAttrService` for the xoxc token (slack-cli's default).
  public static let xoxcService = "slack-xoxc-token"
  /// `kSecAttrService` for the xoxd cookie (slack-cli's default).
  public static let xoxdService = "slack-xoxd-token"

  /// `kSecAttrAccount` for both items: the current login name, matching the
  /// default slack-cli uses (`os/user.Current().Username`). `loginName` is
  /// injectable for tests; the `"slack-cli"` fallback guarantees a non-empty
  /// value in the (practically impossible) case of an empty login name.
  public static func account(loginName: String = NSUserName()) -> String {
    loginName.isEmpty ? "slack-cli" : loginName
  }
}
