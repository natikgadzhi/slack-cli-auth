import Foundation
import Sentry
import SlackAuthKit

/// The single chokepoint for everything this app can ever send off the machine.
/// This is the ONLY file that imports Sentry (a CI grep enforces it). Crash and
/// explicit-error reports only — no analytics, no breadcrumbs, no user/install
/// id, no URLs, no screenshots. Every outgoing event is scrubbed by `Redaction`
/// and dropped if anything secret-shaped survives.
@MainActor
enum Telemetry {
  /// UserDefaults key. Absent ⇒ ON (opt-out default).
  static let enabledKey = "telemetry.crashReportsEnabled"

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
  }

  static func setEnabled(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: enabledKey)
  }

  /// Called once at launch. No-op (the SDK never starts) when disabled or when no
  /// DSN is baked into the build — dev, CI, and open-source builds have no DSN, so
  /// crash reports only ever come from official notarized releases.
  static func start() {
    guard isEnabled else { return }
    guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String,
      !dsn.isEmpty
    else { return }
    SentrySDK.start { options in configure(options, dsn: dsn) }
  }

  /// The ONLY way the rest of the app sends anything. No-op if `start()` didn't
  /// run. The error flows through `scrub` like a crash does.
  static func report(_ error: Error) {
    guard isEnabled else { return }
    SentrySDK.capture(error: error)
  }

  private static func configure(_ options: Options, dsn: String) {
    options.dsn = dsn
    #if DEBUG
      options.environment = "development"
    #else
      options.environment = "production"
    #endif

    // Performance fully off — perf spans record URLs (Slack workspace/API URLs).
    options.tracesSampleRate = 0

    // Auto-instrumentation off — these are the main accidental-data channels.
    options.enableSwizzling = false  // disables most auto-breadcrumbs/network capture at once
    options.enableAutoBreadcrumbTracking = false
    options.enableNetworkBreadcrumbs = false
    options.enableNetworkTracking = false
    options.enableCaptureFailedRequests = false  // never capture HTTP failures (URLs/bodies)
    options.enableAutoSessionTracking = false
    options.enableSpotlight = false

    // No IP, no auto user, no device identifiers we don't set.
    options.sendDefaultPii = false

    // Drop ALL breadcrumbs — belt-and-suspenders over the toggles above.
    options.beforeBreadcrumb = { _ in nil }

    // The scrub: last line of defense on every event we do send.
    options.beforeSend = { event in scrub(event) }
  }

  /// Scrub an outgoing event: strip request/context data, run every
  /// value-bearing string through `Redaction`, and **drop the whole event** if
  /// any value still looks like a secret, a username path, or a Slack endpoint.
  /// Symbol/type names in stack frames are left intact (they carry no data), so
  /// ordinary crashes survive. Pure over the event — unit-tested via `Redaction`.
  nonisolated static func scrub(_ event: Event) -> Event? {
    event.request = nil
    event.user = nil
    event.serverName = nil
    event.extra = nil
    event.context = nil
    event.breadcrumbs = nil

    var values: [String] = []

    if let message = event.message {
      // `formatted` is get-only, so replace the message with a scrubbed one.
      let scrubbed = Redaction.scrubValue(message.formatted)
      event.message = SentryMessage(formatted: scrubbed)
      values.append(scrubbed)
    }

    for exception in event.exceptions ?? [] {
      exception.value = Redaction.scrubValue(exception.value)
      values.append(exception.value)
      for frame in exception.stacktrace?.frames ?? [] {
        if let file = frame.fileName {
          let scrubbed = Redaction.scrubValue(file)
          frame.fileName = scrubbed
          values.append(scrubbed)
        }
      }
    }

    // Fail closed: anything still leaking ⇒ drop the whole event.
    if values.contains(where: Redaction.containsLeak) { return nil }
    return event
  }
}
