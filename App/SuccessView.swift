import SwiftUI

/// The success screen shown once tokens are captured and saved. It celebrates the
/// result, then explains how to use slack-cli with the stored tokens and where
/// those tokens live in the Keychain.
struct SuccessView: View {
  /// e.g. "Saved tokens for Lambda (as natik.gadzhi)."
  let headline: String
  let onDone: () -> Void

  private let repoURL = URL(string: "https://github.com/natikgadzhi/slack-cli")!

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        header
        SlackCLISection(repoURL: repoURL)
        KeychainSection()
        Button("Done", action: onDone)
          .controlSize(.large)
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("doneButton")
      }
      .frame(maxWidth: 540)
      .frame(maxWidth: .infinity)
      .padding(32)
    }
    .accessibilityIdentifier("successScreen")
  }

  private var header: some View {
    VStack(spacing: 10) {
      Image(systemName: "checkmark.seal.fill")
        .font(.system(size: 56))
        .foregroundStyle(.green)
        .symbolRenderingMode(.hierarchical)
        .accessibilityHidden(true)
      Text("You're all set")
        .font(.title)
        .bold()
      Text(headline)
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
  }
}

/// "Use it with slack-cli": Homebrew install + verify, with a link to the repo.
private struct SlackCLISection: View {
  let repoURL: URL

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        Text(
          "slack-cli reads these tokens from your Keychain automatically. "
            + "If you don't have it yet, install it with Homebrew:"
        )
        .foregroundStyle(.secondary)

        CopyableCommand("brew install natikgadzhi/taps/slack-cli")

        Text("Then confirm it can see your new tokens:")
          .foregroundStyle(.secondary)

        CopyableCommand("slack-cli auth check")

        Link(destination: repoURL) {
          Label("slack-cli on GitHub", systemImage: "arrow.up.forward")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 10)
      .padding(.horizontal, 6)
    } label: {
      Label("Use it with slack-cli", systemImage: "terminal")
    }
  }
}

/// "Where your tokens are saved": the two Keychain items and how to inspect them.
private struct KeychainSection: View {
  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        Text(
          "Your tokens are stored in your login Keychain as two items, "
            + "under your macOS account name:"
        )
        .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 6) {
          Label("slack-xoxc-token", systemImage: "key.fill")
          Label("slack-xoxd-token", systemImage: "key.fill")
        }
        .font(.body.monospaced())

        Text("Open Keychain Access and search \u{201C}slack-\u{201D} to see them, or run:")
          .foregroundStyle(.secondary)

        CopyableCommand("security find-generic-password -s slack-xoxc-token")

        Text("Add `-w` to print the secret value.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 10)
      .padding(.horizontal, 6)
    } label: {
      Label("Where your tokens are saved", systemImage: "lock.fill")
    }
  }
}

#Preview("Success") {
  SuccessView(headline: "Saved tokens for Lambda (as natik.gadzhi).", onDone: {})
    .frame(width: 600, height: 720)
}
