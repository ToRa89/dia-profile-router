// Sources/DiaRouterShell/URLResolver.swift
import Foundation
import DiaRouterCore

/// Resolves wrapped/redirected URLs to their real destination before routing.
/// Step A (static) runs first — no network, instant. Step B (HTTP follow)
/// is triggered only for an explicit allowlist of known redirect-service hosts.
public enum URLResolver {

    /// Returns the real destination URL.
    /// Logs the unwrap source (`static` or `http`) when the URL changes.
    public static func resolve(_ url: URL) async -> URL {
        // A: static pattern extraction (SafeLinks, Teams)
        let afterStatic = URLUnwrap.staticUnwrap(url)
        if afterStatic != url {
            RoutingLog.logger.info(
                "unwrap static \(url.host ?? "", privacy: .public) -> \(afterStatic.absoluteString, privacy: .public)")
            return afterStatic
        }

        // B: HTTP redirect follow — only for known redirect-service hosts
        guard let host = url.host?.lowercased(),
              URLUnwrap.httpRedirectHosts.contains(host) else {
            return url
        }

        do {
            let resolved = try await followRedirects(url, timeout: 3.0)
            let scheme = resolved.scheme?.lowercased()
            guard scheme == "http" || scheme == "https" else { return url }
            if resolved != url {
                RoutingLog.logger.info(
                    "unwrap http \(url.host ?? "", privacy: .public) -> \(resolved.absoluteString, privacy: .public)")
            }
            return resolved
        } catch {
            RoutingLog.logger.info("unwrap http failed for \(url.host ?? "", privacy: .public): \(String(describing: error), privacy: .public)")
            return url
        }
    }

    // MARK: - Private

    // Sends one HEAD request; URLSession follows 3xx internally and returns the final URL.
    // Servers that reject HEAD with 405 will cause a URLError — the caller falls back to the
    // original URL gracefully. Most link-shorteners (go.microsoft.com, aka.ms, bit.ly) support HEAD.
    private static func followRedirects(_ url: URL, timeout: TimeInterval) async throws -> URL {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: request)
        return response.url ?? url
    }
}
