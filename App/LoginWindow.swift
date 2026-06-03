import AppKit
import SlackAuthKit
import SwiftUI
import WebKit

/// Hosts the auth manager's login web view in SwiftUI.
struct LoginWebView: NSViewRepresentable {
  let webView: WKWebView

  func makeNSView(context: Context) -> WKWebView {
    webView.setAccessibilityLabel("Slack sign-in web page")
    webView.setAccessibilityIdentifier("slackLoginWebView")
    return webView
  }

  func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// The window: the Slack sign-in web view, with an opaque cover that fades in the
/// moment authentication completes — so the user never sees their Slack content,
/// just a clean "finishing up" → success flow while tokens are captured and saved.
@MainActor
struct LoginWindowContent: View {
  let manager: SlackAuthManager

  @State private var confirmingClear = false

  var body: some View {
    ZStack {
      LoginWebView(webView: manager.loginWebView)
        .frame(minWidth: 560, minHeight: 680)

      if showsCover {
        LoginCover(
          state: manager.state,
          statusMessage: manager.statusMessage,
          savedHeadline: savedHeadline,
          onRetry: manager.retry,
          onQuit: quit,
          onClear: { confirmingClear = true }
        )
        .transition(.opacity)
      }
    }
    .animation(.easeInOut(duration: 0.28), value: manager.state)
    .confirmationDialog(
      "Clear the stored Slack tokens?", isPresented: $confirmingClear
    ) {
      Button("Clear tokens", role: .destructive, action: manager.clearStoredTokens)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("slack-cli will need new tokens until you sign in again here.")
    }
  }

  private var showsCover: Bool {
    switch manager.state {
    case .finishing, .saved, .failed: true
    case .new, .signingIn: false
    }
  }

  private var savedHeadline: String {
    switch (manager.savedTeam, manager.savedUser) {
    case (.some(let team), .some(let user)): "Saved tokens for \(team) (as \(user))."
    case (.some(let team), nil): "Saved tokens for \(team)."
    default: "Saved your Slack tokens."
    }
  }

  private func quit() {
    NSApplication.shared.terminate(nil)
  }
}

/// The opaque overlay shown once sign-in completes: a spinner while finishing, a
/// confirmation when saved, or an error with retry. Its solid background hides
/// the web view loading behind it.
@MainActor
struct LoginCover: View {
  let state: AuthenticationState
  let statusMessage: String
  let savedHeadline: String
  let onRetry: () -> Void
  let onQuit: () -> Void
  let onClear: () -> Void

  var body: some View {
    ZStack {
      Color(nsColor: .windowBackgroundColor)
        .ignoresSafeArea()
      content
    }
  }

  @ViewBuilder private var content: some View {
    switch state {
    case .finishing:
      finishing
        .frame(maxWidth: 420)
        .padding(40)

    case .saved:
      SuccessView(headline: savedHeadline, onDone: onQuit)

    case .failed(let reason):
      failed(reason)
        .frame(maxWidth: 420)
        .padding(40)

    case .new, .signingIn:
      EmptyView()
    }
  }

  private var finishing: some View {
    VStack(spacing: 16) {
      ProgressView()
        .controlSize(.large)
      Text(statusMessage.isEmpty ? "Finishing sign-in…" : statusMessage)
        .font(.headline)
      Text("Hang tight — capturing and verifying your Slack tokens.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .accessibilityIdentifier("finishingCover")
  }

  private func failed(_ reason: String) -> some View {
    VStack(spacing: 14) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 40))
        .foregroundStyle(.orange)
      Text(reason)
        .font(.headline)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 12) {
        Button("Clear stored tokens", action: onClear)
        Button("Try again", action: onRetry)
          .keyboardShortcut(.defaultAction)
      }
    }
    .accessibilityIdentifier("failedCover")
  }
}
