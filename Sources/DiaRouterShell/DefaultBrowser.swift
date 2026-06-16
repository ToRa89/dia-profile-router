// Sources/DiaRouterShell/DefaultBrowser.swift
import AppKit

public enum DefaultBrowser {
    /// Ist diese App aktuell Standard-Handler für https?
    public static func isDefault() -> Bool {
        guard let url = URL(string: "https://example.com"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: url) else { return false }
        return handler == Bundle.main.bundleURL
    }

    /// Setzt diese App als Standard für http+https (öffnet Systemdialog zur Bestätigung).
    /// Note: The correct Swift name on this SDK is setDefaultApplication(at:toOpenURLsWithScheme:completion:)
    public static func setAsDefault() {
        let appURL = Bundle.main.bundleURL
        for scheme in ["http", "https"] {
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: scheme) { error in
                if let error { NSLog("setDefaultApplication(\(scheme)) failed: \(error)") }
            }
        }
    }
}
