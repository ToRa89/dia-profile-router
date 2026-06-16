// Sources/DiaRouterCore/URLNormalize.swift
import Foundation

public enum URLNormalize {
    /// Kleingeschriebener Host, ohne Trailing-Slash am Pfad.
    public static func host(_ url: URL) -> String {
        (url.host ?? "").lowercased()
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
