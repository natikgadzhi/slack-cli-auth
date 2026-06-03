#if DEBUG
  import Foundation
  import WebKit

  /// Debug-only sink for web-view diagnostics: navigation URLs and forwarded JS
  /// console/error messages. Writes to a fixed file (truncated at launch) and to
  /// stderr, so it's easy to `tail -f` while wiring up the login flow. Compiled
  /// out of release builds entirely.
  ///
  /// Thread-safe via a lock so it can be called from any WebKit callback without
  /// actor ceremony.
  enum WebDebugLog {
    static let path = "/tmp/slackauth-webview.log"

    nonisolated(unsafe) private static var handle: FileHandle? = {
      FileManager.default.createFile(atPath: path, contents: nil)
      return FileHandle(forWritingAtPath: path)
    }()
    private static let lock = NSLock()

    static func write(_ line: String) {
      let data = Data((line + "\n").utf8)
      lock.lock()
      defer { lock.unlock() }
      FileHandle.standardError.write(data)
      handle?.write(data)
    }
  }

  /// Receives the forwarded `console.*` / error messages from the page and writes
  /// them to `WebDebugLog`. Installed as a `WKScriptMessageHandler` named
  /// `slackAuthDebug`, paired with `captureJS` injected at document start.
  final class WebConsoleRelay: NSObject, WKScriptMessageHandler {
    /// Injected into every frame: wraps the console methods and global error
    /// handlers to forward to the native side. Best-effort — wrapped in try/catch
    /// so a missing handler never breaks the page.
    static let captureJS = """
      (function () {
        function send(level, text) {
          try {
            window.webkit.messageHandlers.slackAuthDebug.postMessage({
              level: level, text: text, url: location.href
            });
          } catch (e) {}
        }
        ["log", "info", "warn", "error", "debug"].forEach(function (level) {
          var orig = console[level];
          console[level] = function () {
            send(level, Array.from(arguments).map(String).join(" "));
            if (orig) orig.apply(console, arguments);
          };
        });
        window.addEventListener("error", function (e) {
          send("error", (e.message || "") + " @ " + (e.filename || "") + ":" + (e.lineno || ""));
        });
        window.addEventListener("unhandledrejection", function (e) {
          var r = e.reason;
          send("error", "unhandledrejection: " + (r && r.message ? r.message : String(r)));
        });
      })();
      """

    func userContentController(
      _ controller: WKUserContentController, didReceive message: WKScriptMessage
    ) {
      let dict = message.body as? [String: Any]
      let level = dict?["level"] as? String ?? "log"
      let text = dict?["text"] as? String ?? ""
      let url = dict?["url"] as? String ?? ""
      WebDebugLog.write("[js:\(level)] \(text)   (\(url))")
    }
  }
#endif
