// Sources/DiaRouterShell/AccessibilityPermission.swift
import AppKit
import ApplicationServices

/// Accessibility (TCC) status for this app. Needed for the System-Events menu automation
/// that opens a new profile window when no matching window is open.
public enum AccessibilityPermission {
    /// Whether this process is currently trusted for Accessibility.
    public static func isGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Opens System Settings → Privacy & Security → Accessibility so the user can grant it.
    public static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
