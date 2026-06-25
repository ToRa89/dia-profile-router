// Sources/DiaRouterCore/RuleSuggestion.swift
import Foundation

/// Helpers for turning a chooser decision into a persisted rule.
public enum RuleSuggestion {
    /// Default host pattern for "remember this site": lowercased host without a leading "www.".
    /// Returns nil when there is no host. Deliberately does NOT collapse to a registrable
    /// domain — that would merge distinct tenants like `porsche.sharepoint.com`.
    public static func hostPattern(for url: URL) -> String? {
        let h = URLNormalize.host(url)
        guard !h.isEmpty else { return nil }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    /// Returns a new config with `rule` applied: if a `.host` rule with the same pattern
    /// (case-insensitive) exists, its profile is updated; otherwise the rule is appended.
    public static func appended(_ rule: Rule, to config: RouterConfig) -> RouterConfig {
        var result = config
        let pat = rule.pattern.lowercased()
        if let idx = result.rules.firstIndex(where: {
            $0.matchType == .host && $0.pattern.lowercased() == pat
        }) {
            result.rules[idx].profileDirectory = rule.profileDirectory
        } else {
            result.rules.append(rule)
        }
        return result
    }
}
