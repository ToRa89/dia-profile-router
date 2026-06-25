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

        // 4. Resolve the exact menu item name (handles truncation)
        let submenuItems = try newWindowSubmenuItemNames()
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
    /// unterstützte Teil und darf nicht von einem evtl. nicht unterstützten `set index` /
    /// `set active tab` mitgerissen werden. Schlägt etwas fehl, ist das nie fatal fürs Routing.
    /// `windowUUID == nil` → Frontfenster.
    func bringToFront(windowUUID: String?) {
        // 1. Dia in den Vordergrund (Apple-Event-`activate`, nicht von macOS-Aktivierungs-
        //    restriktionen betroffen wie NSApp.activate).
        _ = try? runner.run(#"tell application "Dia" to activate"#)

        // 2. Best-effort: Ziel-Fenster nach vorne + neuen Tab fokussieren.
        let windowRef = windowUUID.map { "(first window whose id is \"\($0)\")" } ?? "front window"
        let raise = """
        tell application "Dia"
            set w to \(windowRef)
            set index of w to 1
            set active tab of w to last tab of w
        end tell
        """
        _ = try? runner.run(raise)
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
    private func asStringLiteral(_ url: URL) -> String {
        let s = url.absoluteString
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
        return escaped(s)
    }

    private func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
