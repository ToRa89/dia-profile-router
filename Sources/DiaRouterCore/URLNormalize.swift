// Sources/DiaRouterCore/URLNormalize.swift
import Foundation

public enum URLNormalize {
    /// Pseudo-Host für lokale Dateien (`file://`). Solche URLs haben keinen Host, wären damit
    /// im Regelwerk nicht adressierbar und würden in einem namenlosen Chooser-Prompt landen.
    /// Über diesen Pseudo-Host greifen `host`-Regeln (alle lokalen Dateien) genauso wie
    /// `prefix`/`wildcard`-Regeln auf den Dateipfad (`localfile/Users/…`).
    public static let localFileHost = "localfile"

    /// Kleingeschriebener Host, ohne Trailing-Slash am Pfad.
    /// `file://`-URLs liefern immer `localFileHost` — auch Netzwerkpfade wie `file://server/share`,
    /// damit "lokale Datei" im Regelwerk eine einzige, vorhersagbare Bedeutung hat.
    public static func host(_ url: URL) -> String {
        if url.scheme?.lowercased() == "file" { return localFileHost }
        return (url.host ?? "").lowercased()
    }

    /// "host/path" kleingeschrieben, ohne Fragment/Query, ohne Trailing-Slash.
    public static func hostPath(_ url: URL) -> String {
        let h = host(url)
        var p = url.path
        if p.hasSuffix("/") { p.removeLast() }
        return (h + p).lowercased()
    }

    /// Vollständiger normalisierter String für exakte Vergleiche (scheme+host+path, ohne Fragment).
    public static func full(_ url: URL) -> String {
        let scheme = (url.scheme ?? "https").lowercased()
        return "\(scheme)://\(hostPath(url))"
    }
}
