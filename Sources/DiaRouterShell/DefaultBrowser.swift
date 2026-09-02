// Sources/DiaRouterShell/DefaultBrowser.swift
import AppKit
import UniformTypeIdentifiers

public enum DefaultBrowser {
    /// Content types local web documents arrive as. Declared in Info.plist
    /// (`CFBundleDocumentTypes`) and claimed here at runtime.
    static let webDocumentTypes: [UTType] = [
        .html,
        UTType("public.xhtml"),
        UTType("org.w3c.web-archive"),
    ].compactMap { $0 }

    /// Ist diese App aktuell Standard-Handler für https?
    public static func isDefault() -> Bool {
        guard let url = URL(string: "https://example.com"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: url) else { return false }
        return handler == Bundle.main.bundleURL
    }

    /// Ist diese App aktuell Standard-Handler für lokale HTML-Dateien?
    /// Separat geprüft, weil macOS beim Setzen des Standardbrowsers NUR die Schemes http/https
    /// umbiegt — die Dateityp-Zuordnung `public.html` bleibt beim alten Browser hängen.
    public static func isDefaultForLocalHTML() -> Bool {
        guard let handler = NSWorkspace.shared.urlForApplication(toOpen: .html) else { return false }
        return handler == Bundle.main.bundleURL
    }

    /// Setzt diese App als Standard für http+https UND für lokale Web-Dokumente
    /// (öffnet je Zuordnung einen Systemdialog zur Bestätigung).
    /// Note: The correct Swift name on this SDK is setDefaultApplication(at:toOpenURLsWithScheme:completion:)
    public static func setAsDefault() {
        let appURL = Bundle.main.bundleURL
        for scheme in ["http", "https"] {
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: scheme) { error in
                if let error { NSLog("setDefaultApplication(\(scheme)) failed: \(error)") }
            }
        }
        setAsDefaultForLocalHTML()
    }

    /// Claims the local web-document types. `NSWorkspace.setDefaultApplication(at:toOpen:)`
    /// exists only from macOS 14 on; on macOS 13 the (deprecated but functional) LaunchServices
    /// call is the sole option for content types.
    public static func setAsDefaultForLocalHTML() {
        let appURL = Bundle.main.bundleURL
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        for type in webDocumentTypes {
            if #available(macOS 14.0, *) {
                NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type) { error in
                    if let error { NSLog("setDefaultApplication(\(type.identifier)) failed: \(error)") }
                }
            } else {
                let status = LSSetDefaultRoleHandlerForContentType(
                    type.identifier as CFString, .all, bundleID as CFString)
                if status != noErr {
                    NSLog("LSSetDefaultRoleHandlerForContentType(\(type.identifier)) failed: \(status)")
                }
            }
        }
    }
}
