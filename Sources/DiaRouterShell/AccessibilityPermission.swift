// Sources/DiaRouterShell/AccessibilityPermission.swift
import AppKit
import ApplicationServices

/// Accessibility (TCC) status for this app. Needed for the System-Events menu automation that
/// the legacy placement path uses on older Dia builds.
public enum AccessibilityPermission {
    /// Whether this process is currently trusted for Accessibility.
    public static func isGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Asks macOS for Accessibility access and opens the pane where the user grants it.
    ///
    /// The prompt call is the part that matters: it makes macOS register this app in
    /// System Settings → Privacy & Security → Accessibility (listed, switch off), so the user only
    /// flips a switch instead of adding the binary by hand via "+". Flipping it still requires the
    /// user's password — that is the system's business, not ours.
    ///
    /// - Returns: true if access was already granted (then nothing is opened).
    @discardableResult
    public static func request(
        promptForTrust: () -> Bool = { promptForTrust() },
        openSettingsPane: () -> Void = { openSettings() }
    ) -> Bool {
        // Registers the app in the list (and shows the system prompt) as a side effect.
        if promptForTrust() { return true }
        openSettingsPane()
        return false
    }

    /// `AXIsProcessTrusted` with the system prompt enabled — the call that adds this app to the
    /// Accessibility list. Returns true when the process is already trusted.
    public static func promptForTrust() -> Bool {
        // The literal instead of `kAXTrustedCheckOptionPrompt`: that constant is imported as a
        // global `var` and therefore rejected under Swift 6 strict concurrency. Its value is
        // this string, which is API and does not change.
        let key = "AXTrustedCheckOptionPrompt" as CFString
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Opens System Settings → Privacy & Security → Accessibility so the user can grant it.
    public static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
