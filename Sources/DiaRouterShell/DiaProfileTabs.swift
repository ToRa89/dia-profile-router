// Sources/DiaRouterShell/DiaProfileTabs.swift
import Foundation
import os

/// Primary placement path: address Dia's profiles directly through its AppleScript dictionary
/// (`profile` class, `focus`/`move` commands).
///
/// In current Dia builds a profile is a space of tabs *inside* a window — the old
/// `File → New Window → New <Profile> Window` submenu no longer exists. This path therefore
/// needs neither UI scripting nor Accessibility permission, and it addresses the profile by
/// name, so it cannot drift onto a neighbouring profile when profiles are added or removed.
extension DiaController {
    /// One live Dia window with the profiles it offers.
    struct WindowProfiles: Equatable {
        let uuid: String
        /// Window stacking index as reported by Dia (lower == closer to the front).
        let index: Int
        let activeProfile: String?
        let profiles: [String]
    }

    /// Field separator inside one output line. Cannot occur in a profile name or UUID.
    static let fieldDelimiter = "<<|>>"
    /// Separator between profile names within the profile-list field.
    static let listDelimiter = "<<;>>"

    /// Opens `url` in the profile named `profileName`.
    /// - Returns: true when the tab was placed; false when Dia does not expose that profile
    ///   (older Dia build, profile deleted, renamed) so the caller can fall back.
    func openInNamedProfile(url: URL, profileName: String, profileDirectory: String) -> Bool {
        let windows: [WindowProfiles]
        do {
            windows = try windowsWithProfiles()
        } catch {
            RoutingLog.logger.info(
                "profileAPI \(profileDirectory, privacy: .public) -> unavailable: \(String(describing: error), privacy: .public)")
            return false
        }
        guard !windows.isEmpty else {
            RoutingLog.logger.info("profileAPI \(profileDirectory, privacy: .public) -> no windows")
            return false
        }

        let offered = windows.flatMap(\.profiles)
        guard let exactName = DiaProfileNames.resolve(profileName, among: offered) else {
            RoutingLog.logger.info(
                "profileAPI \(profileDirectory, privacy: .public) -> profile \(profileName, privacy: .public) not offered by Dia")
            return false
        }

        // Prefer a window that already shows the target profile — otherwise the frontmost window
        // that offers it (opening there switches that window's visible profile, which is what
        // Dia itself does for a profile-targeted tab).
        let target = windows.first { window in
            window.activeProfile.map { DiaProfileNames.isSameProfile($0, exactName) } ?? false
        } ?? windows.first { $0.profiles.contains(exactName) }

        guard let target else {
            RoutingLog.logger.info("profileAPI \(profileDirectory, privacy: .public) -> no window offers \(exactName, privacy: .public)")
            return false
        }

        do {
            guard try makeTab(url: url, inProfile: exactName, window: target.uuid) else {
                RoutingLog.logger.info("profileAPI \(profileDirectory, privacy: .public) -> window \(target.uuid, privacy: .public) vanished")
                return false
            }
        } catch {
            RoutingLog.logger.info(
                "profileAPI \(profileDirectory, privacy: .public) -> make tab failed: \(String(describing: error), privacy: .public)")
            return false
        }

        activateDia()
        RoutingLog.logger.info(
            "place \(profileDirectory, privacy: .public) -> profile \(exactName, privacy: .public) in window \(target.uuid, privacy: .public)")
        return true
    }

    /// Every live window with its active profile and the profiles it offers, frontmost first.
    /// Both profile lookups are wrapped in `try` inside AppleScript so an older Dia build
    /// (no `profile` class) yields empty profile lists instead of failing the whole script.
    func windowsWithProfiles() throws -> [WindowProfiles] {
        let script = """
        tell application "Dia"
            set rows to {}
            set d to "\(Self.fieldDelimiter)"
            set s to "\(Self.listDelimiter)"
            repeat with w in windows
                set ap to ""
                try
                    set ap to name of active profile of w
                end try
                set pn to {}
                try
                    set pn to name of every profile of w
                end try
                set AppleScript's text item delimiters to s
                set pnText to pn as text
                set end of rows to ((id of w) & d & (index of w) & d & ap & d & pnText)
            end repeat
        end tell
        set AppleScript's text item delimiters to linefeed
        return rows as text
        """
        return parseWindowProfiles(try runner.run(script))
    }

    func parseWindowProfiles(_ out: String) -> [WindowProfiles] {
        out.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> WindowProfiles? in
                let fields = line.components(separatedBy: Self.fieldDelimiter)
                guard fields.count >= 4 else { return nil }
                let uuid = fields[0].trimmingCharacters(in: .whitespaces)
                guard !uuid.isEmpty else { return nil }
                let active = fields[2].trimmingCharacters(in: .whitespaces)
                let profiles = fields[3]
                    .components(separatedBy: Self.listDelimiter)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && $0 != "missing value" }
                return WindowProfiles(
                    uuid: uuid,
                    index: Int(fields[1].trimmingCharacters(in: .whitespaces)) ?? Int.max,
                    activeProfile: active.isEmpty || active == "missing value" ? nil : active,
                    profiles: profiles)
            }
            .sorted { $0.index < $1.index }
    }

    /// Creates the tab inside `profileName` of the given window and focuses it.
    /// - Returns: false when no live window carries that UUID any more.
    func makeTab(url: URL, inProfile profileName: String, window uuid: String) throws -> Bool {
        // `first window whose id is …` breaks on a type-coercion error in Dia, so the window is
        // located with an explicit repeat loop (same reason as in bringToFront).
        let script = """
        tell application "Dia"
            set theTab to missing value
            repeat with w in windows
                if id of w is "\(escaped(uuid))" then
                    set theTab to make new tab at end of tabs of profile "\(escaped(profileName))" of w ¬
                        with properties {URL:"\(asStringLiteral(url))"}
                    exit repeat
                end if
            end repeat
            if theTab is missing value then return "MISSING"
            try
                focus theTab
            end try
            return "OK"
        end tell
        """
        return try runner.run(script).contains("OK")
    }

    /// Brings Dia forward. Best effort: `focus` already raises the window, but the app itself
    /// still needs the Apple-event `activate` or the link opens behind the current app.
    func activateDia() {
        do {
            _ = try runner.run(#"tell application "Dia" to activate"#)
        } catch {
            RoutingLog.logger.info("activate failed: \(String(describing: error), privacy: .public)")
        }
    }
}
