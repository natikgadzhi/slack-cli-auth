/// One Slack workspace the signed-in session can reach, with its workspace-scoped
/// `xoxc` token. A single login often yields several of these; the user picks one
/// to store (slack-cli holds exactly one `xoxc`).
public struct Workspace: Sendable, Equatable, Identifiable {
  /// Slack team id (e.g. `T01ABCDEF`). Stable identity for the picker.
  public let teamID: String
  /// Display name, e.g. "Acme Inc". Falls back to the domain or team id.
  public let name: String
  /// Subdomain, e.g. `acme` for `acme.slack.com`. May be empty.
  public let domain: String
  /// Full workspace URL if present, e.g. `https://acme.slack.com/`.
  public let url: String
  /// The workspace-scoped `xoxc-…` token.
  public let xoxc: String

  public var id: String { teamID }

  public init(teamID: String, name: String, domain: String, url: String, xoxc: String) {
    self.teamID = teamID
    self.name = name
    self.domain = domain
    self.url = url
    self.xoxc = xoxc
  }
}
