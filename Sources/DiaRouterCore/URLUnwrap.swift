import Foundation

/// Strips known URL wrappers before routing. Pure static logic — no network access.
public enum URLUnwrap {

    /// Domains that are pure link-shorteners/redirectors handled by HTTP follow (used by URLResolver).
    public static let httpRedirectHosts: Set<String> = [
        "go.microsoft.com",
        "aka.ms",
        "bit.ly",
        "t.co",
        "ow.ly",
        "tinyurl.com",
    ]

    /// Returns the real destination URL by extracting encoded target parameters from known wrappers.
    /// Returns `url` unchanged when no wrapper pattern is detected.
    public static func staticUnwrap(_ url: URL) -> URL {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else { return url }

        // Outlook SafeLinks — all regional variants end with this suffix
        if host.hasSuffix(".safelinks.protection.outlook.com") ||
            host == "safelinks.protection.outlook.com" {
            return queryParam("url", in: components).flatMap(URL.init) ?? url
        }

        // Microsoft Teams — file links use objectUrl=, meeting/other redirect links use url=
        if host == "teams.microsoft.com" {
            if let extracted = queryParam("objectUrl", in: components).flatMap(URL.init) {
                return extracted
            }
            if let extracted = queryParam("url", in: components).flatMap(URL.init) {
                return extracted
            }
        }

        return url
    }

    // MARK: - Private

    private static func queryParam(_ name: String, in components: URLComponents) -> String? {
        components.queryItems?.first(where: { $0.name == name })?.value
    }
}
