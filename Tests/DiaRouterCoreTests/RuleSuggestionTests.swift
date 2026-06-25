// Tests/DiaRouterCoreTests/RuleSuggestionTests.swift
import Testing
import Foundation
@testable import DiaRouterCore

@Test func hostPatternStripsLeadingWWWAndLowercases() {
    #expect(RuleSuggestion.hostPattern(for: URL(string: "https://WWW.NeueKunde.de/angebot")!) == "neuekunde.de")
}

@Test func hostPatternKeepsMultiTenantSubdomain() {
    #expect(RuleSuggestion.hostPattern(for: URL(string: "https://porsche.sharepoint.com/sites/x")!)
            == "porsche.sharepoint.com")
}

@Test func hostPatternIsNilWhenNoHost() {
    #expect(RuleSuggestion.hostPattern(for: URL(string: "file:///tmp/x")!) == nil)
}

@Test func appendedAddsNewRule() {
    let cfg = RouterConfig(rules: [], defaultProfileDirectory: "Profile 6")
    let out = RuleSuggestion.appended(
        Rule(matchType: .host, pattern: "neuekunde.de", profileDirectory: "Profile 9"), to: cfg)
    #expect(out.rules.count == 1)
    #expect(out.rules[0].pattern == "neuekunde.de")
    #expect(out.rules[0].profileDirectory == "Profile 9")
}

@Test func appendedUpdatesProfileForExistingHostPattern() {
    let cfg = RouterConfig(
        rules: [Rule(matchType: .host, pattern: "neuekunde.de", profileDirectory: "Profile 6")],
        defaultProfileDirectory: "Profile 6")
    let out = RuleSuggestion.appended(
        Rule(matchType: .host, pattern: "NeueKunde.de", profileDirectory: "Profile 9"), to: cfg)
    #expect(out.rules.count == 1)                       // no duplicate
    #expect(out.rules[0].profileDirectory == "Profile 9")
}
