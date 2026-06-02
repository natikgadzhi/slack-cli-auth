import AppKit
import SlackAuthKit
import SwiftUI

/// A single-window macOS app: open it, sign in to Slack, pick a workspace, and
/// the captured tokens land in the Keychain for slack-cli. Quits when its window
/// closes.
@main
struct SlackAuthApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var manager = SlackAuthManager(secretStore: KeychainSlackSecretStore())

  var body: some Scene {
    Window("Slack Auth", id: "login") {
      LoginWindowContent(manager: manager)
        .onAppear {
          Telemetry.start()
          manager.onError = { Telemetry.report($0) }
          manager.startLogin()
        }
    }
    .windowResizability(.contentSize)
    .commands {
      CommandGroup(replacing: .appInfo) {
        Button("About Slack Auth") { About.showPanel() }
      }
    }
  }
}

/// Quit after the last (only) window closes — this is a one-shot utility, not a
/// menu-bar resident.
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
}
