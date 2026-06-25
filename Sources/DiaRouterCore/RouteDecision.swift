// Sources/DiaRouterCore/RouteDecision.swift
import Foundation

/// Outcome of evaluating routing rules for a URL.
public enum RouteDecision: Equatable, Sendable {
    /// A rule matched → route directly to this profile directory.
    case matched(profileDirectory: String)
    /// No rule matched → ask the user. `host` is the normalized host (for prompt + rule suggestion).
    case needsChoice(host: String)
}

extension RuleEngine {
    /// Decide how to route a URL: a matched rule, or that a prompt is needed.
    public func decide(for url: URL) -> RouteDecision {
        if let rule = matchedRule(for: url) {
            return .matched(profileDirectory: rule.profileDirectory)
        }
        return .needsChoice(host: URLNormalize.host(url))
    }
}
