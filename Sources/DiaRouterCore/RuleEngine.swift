// Sources/DiaRouterCore/RuleEngine.swift
import Foundation

public struct RuleEngine: Sendable {
    public let config: RouterConfig
    public init(config: RouterConfig) { self.config = config }

    /// Liefert die Ziel-Profilverzeichnis-ID; bei keinem Treffer das Default-Profil.
    public func profileDirectory(for url: URL) -> String {
        matchedRule(for: url)?.profileDirectory ?? config.defaultProfileDirectory
    }

    public func matchedRule(for url: URL) -> Rule? {
        config.rules.first { matches($0, url) }
    }

    private func matches(_ rule: Rule, _ url: URL) -> Bool {
        // An empty pattern is never a valid rule — guard prevents accidental catch-all.
        guard !rule.pattern.isEmpty else { return false }
        let host = URLNormalize.host(url)
        let hostPath = URLNormalize.hostPath(url)
        switch rule.matchType {
        case .exact:
            return URLNormalize.full(url) == rule.pattern.lowercased()
                || hostPath == rule.pattern.lowercased()
        case .prefix:
            return hostPath.hasPrefix(rule.pattern.lowercased())
        case .host:
            let p = rule.pattern.lowercased()
            return host == p || host.hasSuffix("." + p)
        case .wildcard:
            let target = rule.pattern.contains("/") ? hostPath : host
            return Wildcard.matches(pattern: rule.pattern.lowercased(), value: target)
        }
    }
}
