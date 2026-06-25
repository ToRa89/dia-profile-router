// Tests/DiaRouterCoreTests/RouteDecisionTests.swift
import Testing
import Foundation
@testable import DiaRouterCore

@Test func decideReturnsMatchedWhenRuleMatches() {
    let cfg = RouterConfig(
        rules: [Rule(matchType: .host, pattern: "example.com", profileDirectory: "Profile 9")],
        defaultProfileDirectory: "Profile 6")
    let engine = RuleEngine(config: cfg)
    #expect(engine.decide(for: URL(string: "https://app.example.com/x")!)
            == .matched(profileDirectory: "Profile 9"))
}

@Test func decideReturnsNeedsChoiceWithHostWhenNoRuleMatches() {
    let engine = RuleEngine(config: RouterConfig(rules: [], defaultProfileDirectory: "Profile 6"))
    #expect(engine.decide(for: URL(string: "https://www.unknown.test/abc")!)
            == .needsChoice(host: "www.unknown.test"))
}
