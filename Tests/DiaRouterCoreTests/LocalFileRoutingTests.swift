// Tests/DiaRouterCoreTests/LocalFileRoutingTests.swift
import Testing
import Foundation
import DiaRouterCore

// A file:// URL has no host, so without normalization every local file would land in
// `needsChoice(host: "")` — an unnamed prompt whose "remember" produces no usable rule.
// The pseudo-host makes local files a first-class, rule-addressable target.

@Test func fileURLNormalizesToPseudoHost() {
    let url = URL(fileURLWithPath: "/Users/tester/Downloads/Report.html")
    #expect(URLNormalize.host(url) == URLNormalize.localFileHost)
    #expect(URLNormalize.hostPath(url) == "localfile/users/tester/downloads/report.html")
}

@Test func hostRuleForPseudoHostMatchesAnyLocalFile() {
    let engine = RuleEngine(config: RouterConfig(
        rules: [Rule(matchType: .host, pattern: "localfile", profileDirectory: "Profile 9")],
        defaultProfileDirectory: "Default"))
    #expect(engine.decide(for: URL(fileURLWithPath: "/tmp/a.html"))
        == .matched(profileDirectory: "Profile 9"))
    #expect(engine.decide(for: URL(fileURLWithPath: "/Users/tester/x/y.html"))
        == .matched(profileDirectory: "Profile 9"))
}

@Test func unmatchedLocalFileAsksWithPseudoHost() {
    let engine = RuleEngine(config: RouterConfig(rules: [], defaultProfileDirectory: "Default"))
    #expect(engine.decide(for: URL(fileURLWithPath: "/tmp/a.html"))
        == .needsChoice(host: "localfile"))
}

@Test func pathRulesWorkForLocalFilesViaPseudoHost() {
    let engine = RuleEngine(config: RouterConfig(
        rules: [
            Rule(matchType: .prefix, pattern: "localfile/Users/tester/clientb", profileDirectory: "Profile 7"),
            Rule(matchType: .wildcard, pattern: "localfile/*/invoices/*", profileDirectory: "Profile 8"),
        ],
        defaultProfileDirectory: "Default"))
    #expect(engine.profileDirectory(for: URL(fileURLWithPath: "/Users/tester/clientb/deck.html")) == "Profile 7")
    #expect(engine.profileDirectory(for: URL(fileURLWithPath: "/Users/tester/invoices/2026.html")) == "Profile 8")
    #expect(engine.profileDirectory(for: URL(fileURLWithPath: "/Users/tester/other.html")) == "Default")
}

@Test func localFileSuggestsPseudoHostAsRememberPattern() {
    #expect(RuleSuggestion.hostPattern(for: URL(fileURLWithPath: "/tmp/a.html")) == "localfile")
}

@Test func httpURLsKeepTheirRealHost() {
    let url = URL(string: "https://www.Example.com/a/")!
    #expect(URLNormalize.host(url) == "www.example.com")
    #expect(URLNormalize.hostPath(url) == "www.example.com/a")
}
