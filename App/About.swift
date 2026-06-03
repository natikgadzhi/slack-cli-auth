import AppKit

/// The app's About panel. Uses the standard macOS About panel (icon + name +
/// version) enriched via its credits field with a one-line summary and links to
/// this repo and the companion CLI it feeds.
enum About {
  private static let summary = """
    Sign in to Slack in a web view and store the xoxc/xoxd tokens the slack-cli \
    needs — in your Keychain, on your own machine.
    """
  private static let repo = URL(string: "https://github.com/natikgadzhi/slack-cli-auth")!
  private static let companion = URL(string: "https://github.com/natikgadzhi/slack-cli")!
  private static let security = URL(
    string: "https://github.com/natikgadzhi/slack-cli-auth/blob/main/SECURITY.md")!

  @MainActor static func showPanel() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits()])
  }

  private static func credits() -> NSAttributedString {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.paragraphSpacing = 8
    let base: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
      .foregroundColor: NSColor.secondaryLabelColor,
      .paragraphStyle: style,
    ]
    let text = NSMutableAttributedString(string: summary + "\n\n", attributes: base)
    text.append(versionLine(base))
    text.append(NSAttributedString(string: "\n\n", attributes: base))
    text.append(linkRun("View source on GitHub", repo, base))
    text.append(NSAttributedString(string: "\n", attributes: base))
    text.append(NSAttributedString(string: "Companion CLI: ", attributes: base))
    text.append(linkRun("slack-cli", companion, base))
    text.append(NSAttributedString(string: "\n", attributes: base))
    text.append(linkRun("Privacy & Security", security, base))
    return text
  }

  /// `Version X (build N) · abc1234` — the commit SHA is baked in at release time
  /// (empty on local/dev builds, which render "local build" with no link).
  private static func versionLine(_ base: [NSAttributedString.Key: Any]) -> NSAttributedString {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    let line = NSMutableAttributedString(
      string: "Version \(version) (build \(build)) · ", attributes: base)
    if let sha = (info?["GitCommitSHA"] as? String), !sha.isEmpty {
      let commitURL = repo.appendingPathComponent("commit").appendingPathComponent(sha)
      line.append(linkRun(String(sha.prefix(7)), commitURL, base))
    } else {
      line.append(NSAttributedString(string: "local build", attributes: base))
    }
    return line
  }

  private static func linkRun(
    _ text: String, _ url: URL, _ base: [NSAttributedString.Key: Any]
  ) -> NSAttributedString {
    var attrs = base
    attrs[.link] = url
    return NSAttributedString(string: text, attributes: attrs)
  }
}
