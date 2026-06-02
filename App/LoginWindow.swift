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

@MainActor
struct LoginWindowContent: View {
  let manager: SlackAuthManager

  @State private var selectedTeamID: String?
  @State private var confirmingClear = false

  var body: some View {
    VStack(spacing: 0) {
      LoginWebView(webView: manager.loginWebView)
        .frame(minWidth: 560, minHeight: 660)

      Divider()
      statusBar
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }
    .animation(.snappy, value: manager.state)
    .confirmationDialog(
      "Clear the stored Slack tokens?", isPresented: $confirmingClear
    ) {
      Button("Clear tokens", role: .destructive) { manager.clearStoredTokens() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("slack-cli will need new tokens until you sign in again here.")
    }
  }

  /// The footer changes with the flow: a hint while signing in, the workspace
  /// picker once tokens are captured, progress while validating, and a result.
  @ViewBuilder private var statusBar: some View {
    switch manager.state {
    case .new, .authenticating:
      signingInHint
    case .awaitingSelection:
      workspacePicker
    case .validating:
      HStack(spacing: 10) {
        ProgressView().controlSize(.small)
        Text("Verifying tokens with Slack…")
      }
      .accessibilityIdentifier("validatingStatus")
    case .saved:
      savedResult
    case .failed(let reason):
      failureRow(reason)
    }
  }

  private var signingInHint: some View {
    HStack(spacing: 10) {
      Image(systemName: "person.badge.key")
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text("Sign in to Slack above.")
          .font(.system(size: 13, weight: .medium))
        Text("Once you're in, your workspaces will appear here to choose from.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      clearButton
    }
    .accessibilityIdentifier("signingInHint")
  }

  private var workspacePicker: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Save tokens for this workspace")
          .font(.system(size: 13, weight: .medium))
        Picker("Workspace", selection: $selectedTeamID) {
          ForEach(manager.workspaces) { workspace in
            Text(workspaceLabel(workspace)).tag(Optional(workspace.teamID))
          }
        }
        .labelsHidden()
        .frame(maxWidth: 320)
        .accessibilityIdentifier("workspacePicker")
      }
      Spacer()
      Button("Save to Keychain", action: save)
        .keyboardShortcut(.defaultAction)
        .disabled(resolvedSelection == nil)
        .accessibilityIdentifier("saveButton")
    }
    .onAppear { ensureSelection() }
  }

  private var savedResult: some View {
    HStack(spacing: 10) {
      Image(systemName: "checkmark.seal.fill")
        .foregroundStyle(.green)
      VStack(alignment: .leading, spacing: 2) {
        Text(savedHeadline)
          .font(.system(size: 13, weight: .medium))
        Text("slack-cli will pick these up automatically. You can quit now.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Quit", action: quit)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("quitButton")
    }
    .accessibilityIdentifier("savedResult")
  }

  private func failureRow(_ reason: String) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      Text(reason)
        .font(.system(size: 13))
        .fixedSize(horizontal: false, vertical: true)
      Spacer()
      Button("Try again", action: manager.retrySelection)
        .accessibilityIdentifier("retryButton")
    }
    .accessibilityIdentifier("failureRow")
  }

  private var clearButton: some View {
    Button("Clear stored tokens") { confirmingClear = true }
      .controlSize(.small)
      .accessibilityIdentifier("clearButton")
  }

  // MARK: - Helpers

  private var resolvedSelection: Workspace? {
    manager.workspaces.first { $0.teamID == selectedTeamID }
  }

  private var savedHeadline: String {
    switch (manager.savedTeam, manager.savedUser) {
    case (.some(let team), .some(let user)):
      return "Saved tokens for \(team) (as \(user))."
    case (.some(let team), nil):
      return "Saved tokens for \(team)."
    default:
      return "Saved your Slack tokens."
    }
  }

  private func workspaceLabel(_ workspace: Workspace) -> String {
    if !workspace.domain.isEmpty, workspace.domain != workspace.name {
      return "\(workspace.name) (\(workspace.domain).slack.com)"
    }
    return workspace.name
  }

  private func ensureSelection() {
    if resolvedSelection == nil {
      selectedTeamID = manager.workspaces.first?.teamID
    }
  }

  private func save() {
    guard let workspace = resolvedSelection else { return }
    Task { await manager.select(workspace) }
  }

  private func quit() {
    NSApplication.shared.terminate(nil)
  }
}
