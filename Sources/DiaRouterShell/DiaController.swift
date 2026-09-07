// Sources/DiaRouterShell/DiaController.swift
import Foundation
import os
import DiaRouterCore

@MainActor
public final class DiaController {
    let runner: any AppleScriptRunning
    /// Persists the window UUID opened for each profileDirectory across calls.
    /// Internal so tests can seed the cache via @testable; external callers see it as read-only.
    var createdWindowCache: [String: String] = [:]   // profileDirectory -> windowUUID

    public init(runner: any AppleScriptRunning) {
        self.runner = runner
    }

    /// - Parameter belongsToTargetProfile: returns true if a window's active-tab URL indicates
    ///   the window belongs to the target profile (used to reuse already-open windows the app
    ///   did not itself create). Router supplies this from the user's routing rules.
    public func open(
        url: URL,
        profileDirectory: String,
        profiles: [Profile],
        belongsToTargetProfile: (URL) -> Bool = { _ in false }
    ) throws {
        // Preferred path: address the profile BY NAME through Dia's profile API (see
        // DiaProfileTabs.swift). No Accessibility, no menu positions, no window guessing.
        if let profileName = profiles.first(where: { $0.directory == profileDirectory })?.name,
           openInNamedProfile(url: url, profileName: profileName, profileDirectory: profileDirectory) {
            return
        }
        try openViaWindowMenu(
            url: url, profileDirectory: profileDirectory, profiles: profiles,
            belongsToTargetProfile: belongsToTargetProfile)
    }

    /// Fallback for Dia builds without the profile API, where each profile had its own window
    /// created via `File → New Window → New <Profile> Window`.
    func openViaWindowMenu(
        url: URL,
        profileDirectory: String,
        profiles: [Profile],
        belongsToTargetProfile: (URL) -> Bool
    ) throws {
        let live = try liveWindowUUIDs()

        // 1. Cache hit: reuse the window we previously opened/confirmed for this profile if still alive
        if let cached = createdWindowCache[profileDirectory], live.contains(cached) {
            RoutingLog.logger.info("place \(profileDirectory, privacy: .public) -> cache \(cached, privacy: .public)")
            try openTab(url: url, inWindow: cached)
            return
        }

        // 2. ACTIVE TAB WINS — reuse a window whose *active* tab routes (by the user's rules) to this
        //    profile. Strongest signal, lowest ambiguity. (The unreliable "any tab" pass was removed.)
        let activeTabs = try windowsWithActiveURLs()
        if let match = activeTabs.first(where: { $0.url.map(belongsToTargetProfile) ?? false }) {
            createdWindowCache[profileDirectory] = match.uuid
            RoutingLog.logger.info("place \(profileDirectory, privacy: .public) -> activeTab \(match.uuid, privacy: .public)")
            try openTab(url: url, inWindow: match.uuid)
            return
        }

        // 3. Resolve display name for the target profile
        guard let profileName = profiles.first(where: { $0.directory == profileDirectory })?.name else {
            RoutingLog.logger.info("place \(profileDirectory, privacy: .public) -> frontFallback (unknown profile)")
            try openTabInFrontWindow(url: url)
            return
        }

        // 4. Resolve the exact menu item name (handles truncation). A missing submenu is a
        //    normal state in current Dia builds — treat the query failure as "no items" instead
        //    of throwing, so routing degrades to the front window rather than to NSWorkspace.
        let submenuItems = (try? newWindowSubmenuItemNames()) ?? []
        guard let menuItemName = DiaMenu.newWindowMenuItem(forProfileName: profileName, among: submenuItems) else {
            RoutingLog.logger.info("place \(profileDirectory, privacy: .public) -> frontFallback (no menu item)")
            try openTabInFrontWindow(url: url)
            return
        }

        // 5. Click menu item, poll for the new window
        let preClickUUIDs = Set(try liveWindowUUIDs())
        try clickNewWindowItem(menuItemName)
        if let newUUID = try pollForNewWindow(preClickUUIDs: preClickUUIDs) {
            createdWindowCache[profileDirectory] = newUUID
            RoutingLog.logger.info("place \(profileDirectory, privacy: .public) -> newWindow \(newUUID, privacy: .public) via \(menuItemName, privacy: .public)")
            try openTab(url: url, inWindow: newUUID)
        } else {
            RoutingLog.logger.info("place \(profileDirectory, privacy: .public) -> frontFallback (poll timeout)")
            try openTabInFrontWindow(url: url)
        }
    }

    // MARK: - AppleScript helpers

    func liveWindowUUIDs() throws -> [String] {
        // NSAppleScript returns nil for `stringValue` when the result is a list, so we must
        // coerce the list to a newline-delimited string inside AppleScript itself.
        let script = #"""
        tell application "Dia"
            set theIDs to id of every window
        end tell
        set AppleScript's text item delimiters to linefeed
        return theIDs as text
        """#
        return parseList(try runner.run(script))
    }

    /// Returns each live window's UUID paired with its active tab URL (nil if unavailable).
    func windowsWithActiveURLs() throws -> [(uuid: String, url: URL?)] {
        // Build "uuid<DELIM>activeURL" lines inside AppleScript (NSAppleScript returns nil
        // stringValue for list results, so we coerce to text). NOTE: inside `tell application
        // "Dia"`, the word `tab` resolves to Dia's *tab class*, not the tab character — so we
        // use an explicit unambiguous delimiter that cannot occur in a URL.
        let delim = "<<|>>"
        let script = """
        tell application "Dia"
            set rows to {}
            set d to "\(delim)"
            repeat with w in windows
                set u to ""
                try
                    set u to URL of active tab of w
                end try
                set end of rows to ((id of w) & d & u)
            end repeat
        end tell
        set AppleScript's text item delimiters to linefeed
        return rows as text
        """
        let out = try runner.run(script)
        return out.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line -> (uuid: String, url: URL?)? in
            let parts = line.components(separatedBy: delim)
            guard let uuid = parts.first, !uuid.isEmpty else { return nil }
            let urlStr = parts.count > 1 ? parts[1] : ""
            return (uuid, urlStr.isEmpty ? nil : URL(string: urlStr))
        }
    }

    func newWindowSubmenuItemNames() throws -> [String] {
        // Same NSAppleScript list-coercion requirement as liveWindowUUIDs(). Menu item names
        // contain no newlines, so a linefeed delimiter is unambiguous.
        let script = #"""
        tell application "Dia" to activate
        tell application "System Events"
            tell process "Dia"
                set theNames to name of every menu item of menu 1 of menu item "New Window" of menu 1 of menu bar item "File" of menu bar 1
            end tell
        end tell
        set AppleScript's text item delimiters to linefeed
        return theNames as text
        """#
        return parseList(try runner.run(script))
    }

    /// Splits a newline-delimited AppleScript text result, trimming and dropping empties / `missing value`.
    private func parseList(_ out: String) -> [String] {
        out
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "missing value" }
    }

    func clickNewWindowItem(_ exactName: String) throws {
        let script = """
        tell application "Dia" to activate
        tell application "System Events"
            tell process "Dia"
                click menu item "\(escaped(exactName))" of menu 1 of menu item "New Window" of menu 1 of menu bar item "File" of menu bar 1
            end tell
        end tell
        """
        try runner.run(script)
    }

    func openTab(url: URL, inWindow uuid: String) throws {
        let script = """
        tell application "Dia"
            make new tab at end of tabs of (first window whose id is "\(uuid)") with properties {URL:"\(asStringLiteral(url))"}
        end tell
        """
        try runner.run(script)
        bringToFront(windowUUID: uuid)
    }

    func openTabInFrontWindow(url: URL) throws {
        let script = """
        tell application "Dia"
            make new tab at end of tabs of front window with properties {URL:"\(asStringLiteral(url))"}
        end tell
        """
        try runner.run(script)
        bringToFront(windowUUID: nil)
    }

    /// Holt Dia (und das Ziel-Fenster) nach vorne und aktiviert den eben geöffneten Tab —
    /// sonst landet der Link „silent" im Hintergrund, wenn ein bestehendes Fenster wiederverwendet
    /// wird (nur der Neu-Fenster-Pfad aktivierte Dia bisher implizit über den Menü-Klick).
    ///
    /// Bewusst best-effort und in getrennten Skripten: `activate` ist der robuste, immer
    /// unterstützte Teil und darf nicht von einem evtl. fehlschlagenden `focus` mitgerissen
    /// werden. Schlägt etwas fehl, ist das nie fatal fürs Routing. `windowUUID == nil` →
    /// Frontfenster.
    ///
    /// `focus` (statt `set index`/`set active tab`) ist Dias offiziell dokumentierter Befehl
    /// dafür ("Focus a tab or profile, bringing its window forward if needed.") — siehe auch
    /// `makeTab(url:inProfile:window:)` in DiaProfileTabs.swift, das denselben Befehl für den
    /// bevorzugten Profil-API-Pfad nutzt. Laut Dias eigenem `sdef` sind `index`, `active tab`
    /// und `active profile` am `window` READ-ONLY (access="r") — jeder Versuch, sie per `set`
    /// zu schreiben, schlägt daher IMMER mit einem AppleScript-Fehler fehl, unabhängig davon,
    /// wie das Fenster referenziert wird. Das war die eigentliche Ursache dafür, dass über
    /// diesen Legacy-Fallback (Dia-Build ohne Profil-API) gerouteter Tabs im Hintergrundfenster
    /// landeten, während sichtbar das zuvor aktive Profil im Vordergrund blieb.
    func bringToFront(windowUUID: String?) {
        let target = windowUUID ?? "<front>"
        RoutingLog.logger.info("bringToFront start uuid=\(target, privacy: .public)")

        // 1. Dia in den Vordergrund (Apple-Event-`activate`, nicht von macOS-Aktivierungs-
        //    restriktionen betroffen wie NSApp.activate).
        do {
            _ = try runner.run(#"tell application "Dia" to activate"#)
            RoutingLog.logger.info("bringToFront activate ok uuid=\(target, privacy: .public)")
        } catch {
            RoutingLog.logger.info("bringToFront activate FAILED uuid=\(target, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }

        // 2. Best-effort: den eben erzeugten Tab fokussieren (bringt sein Fenster nach vorne).
        let raise: String
        if let uuid = windowUUID {
            raise = """
            tell application "Dia"
                focus (last tab of (first window whose id is "\(uuid)"))
            end tell
            """
        } else {
            raise = """
            tell application "Dia"
                focus (last tab of front window)
            end tell
            """
        }
        do {
            _ = try runner.run(raise)
            RoutingLog.logger.info("bringToFront raise ok uuid=\(target, privacy: .public)")
        } catch {
            RoutingLog.logger.info("bringToFront raise FAILED uuid=\(target, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }

    /// Polls until a window UUID appears that wasn't in preClickUUIDs, or times out (~2s, ~150ms interval).
    private func pollForNewWindow(preClickUUIDs: Set<String>) throws -> String? {
        let maxTries = 13
        for _ in 0..<maxTries {
            Thread.sleep(forTimeInterval: 0.15)
            let current = try liveWindowUUIDs()
            if let newUUID = current.first(where: { !preClickUUIDs.contains($0) }) {
                return newUUID
            }
        }
        return nil
    }

    // MARK: - String escaping

    /// Percent-encodes control characters that would break an AppleScript string literal,
    /// then applies the standard backslash-escape for `\` and `"`.
    func asStringLiteral(_ url: URL) -> String {
        let s = url.absoluteString
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
        return escaped(s)
    }

    func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
