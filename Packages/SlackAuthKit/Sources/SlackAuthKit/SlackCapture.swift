import Foundation

/// Pure extraction logic for the Slack web session: the JavaScript that reads the
/// workspace tokens out of `localStorage`, and the parser that turns its result
/// into `[Workspace]`. The `d` cookie is read separately from the cookie store
/// (it's HttpOnly — invisible to JavaScript); see `SlackAuthManager`.
///
/// Kept dependency-free so the parser is unit-tested by plain `swift test`.
public enum SlackCapture {
  /// Read `localConfig_v2` from the page's `localStorage` and return each team
  /// that carries an `xoxc` token. Runs in the page content world via
  /// `callAsyncJavaScript`, so it uses `return` and may `await`.
  public static let localConfigReadJS = """
    const out = { ok: false, hasLocalConfig: false, teamCount: 0, teams: [] };
    try {
      const raw = localStorage.getItem("localConfig_v2");
      if (!raw) return out;
      out.hasLocalConfig = true;
      const cfg = JSON.parse(raw);
      const teams = cfg && cfg.teams ? cfg.teams : {};
      const ids = Object.keys(teams);
      out.teamCount = ids.length;
      for (const id of ids) {
        const t = teams[id] || {};
        const token = typeof t.token === "string" ? t.token : "";
        if (token.indexOf("xoxc-") !== 0) continue;
        out.teams.push({
          id: typeof t.id === "string" && t.id ? t.id : id,
          name: typeof t.name === "string" ? t.name : "",
          domain: typeof t.domain === "string" ? t.domain : "",
          url: typeof t.url === "string" ? t.url : "",
          token: token,
        });
      }
      out.ok = out.teams.length > 0;
      return out;
    } catch (e) {
      out.error = String(e);
      return out;
    }
    """

  /// Parse the JS result into workspaces. Returns `nil` (not an empty array) when
  /// the page has no usable tokens yet, so the caller can keep polling. A
  /// `Workspace` is emitted only when its `xoxc` token is present and well-formed.
  public static func parse(_ result: Any?) -> [Workspace]? {
    guard let dict = result as? [String: Any],
      let ok = dict["ok"] as? Bool, ok,
      let rawTeams = dict["teams"] as? [[String: Any]], !rawTeams.isEmpty
    else {
      return nil
    }

    var workspaces: [Workspace] = []
    for team in rawTeams {
      guard let token = team["token"] as? String, token.hasPrefix("xoxc-") else { continue }
      let id = (team["id"] as? String) ?? ""
      let domain = (team["domain"] as? String) ?? ""
      let rawName = (team["name"] as? String) ?? ""
      let url = (team["url"] as? String) ?? ""
      // Prefer a real name; fall back to the domain, then the team id, so the
      // picker always has something legible to show.
      let name = !rawName.isEmpty ? rawName : (!domain.isEmpty ? domain : id)
      guard !id.isEmpty else { continue }
      workspaces.append(
        Workspace(teamID: id, name: name, domain: domain, url: url, xoxc: token))
    }
    return workspaces.isEmpty ? nil : workspaces
  }

  /// A secret-free one-line summary of a failed/empty capture, for logging while
  /// polling. Never includes any token value.
  public static func diagnostic(_ result: Any?) -> String {
    guard let dict = result as? [String: Any] else { return "no result" }
    let hasConfig = (dict["hasLocalConfig"] as? Bool) ?? false
    let teamCount = (dict["teamCount"] as? Int) ?? 0
    let tokenTeams = (dict["teams"] as? [[String: Any]])?.count ?? 0
    if let err = dict["error"] as? String { return "js error: \(err)" }
    return "localConfig=\(hasConfig) teams=\(teamCount) withToken=\(tokenTeams)"
  }
}
