// Tests/DiaRouterCoreTests/RuleEngineTests.swift  (Teil 1: Normalisierung)
import Testing
import Foundation
@testable import DiaRouterCore

@Test func normalizeProducesLowercaseHostAndPathWithoutFragment() {
    let url = URL(string: "HTTPS://App.Example.com/jira/secure#frag")!
    #expect(URLNormalize.hostPath(url) == "app.example.com/jira/secure")
    #expect(URLNormalize.host(url) == "app.example.com")
}

@Test func normalizeHandlesMissingPath() {
    let url = URL(string: "https://example.com")!
    #expect(URLNormalize.hostPath(url) == "example.com")
}

// Tests/DiaRouterCoreTests/RuleEngineTests.swift  (Teil 2: RuleEngine)

private func engine(_ rules: [Rule], default def: String = "Profile 6") -> RuleEngine {
    RuleEngine(config: RouterConfig(rules: rules, defaultProfileDirectory: def))
}

@Test func hostRuleMatchesSubdomains() {
    let e = engine([Rule(matchType: .host, pattern: "example.com", profileDirectory: "Profile 10")])
    #expect(e.profileDirectory(for: URL(string: "https://app.example.com/jira")!) == "Profile 10")
    #expect(e.profileDirectory(for: URL(string: "https://example.com")!) == "Profile 10")
}

@Test func prefixRuleMatchesHostPathPrefix() {
    let e = engine([Rule(matchType: .prefix, pattern: "team.example.org/sites/Docs", profileDirectory: "Profile 6")], default: "Profile 4")
    #expect(e.profileDirectory(for: URL(string: "https://team.example.org/sites/Docs/Overview")!) == "Profile 6")
    #expect(e.profileDirectory(for: URL(string: "https://team.example.org/sites/Other")!) == "Profile 4")
}

@Test func exactRuleRequiresFullMatch() {
    let e = engine([Rule(matchType: .exact, pattern: "https://app.example.net/selfservices", profileDirectory: "Profile 6")], default: "Profile 4")
    #expect(e.profileDirectory(for: URL(string: "https://app.example.net/selfservices")!) == "Profile 6")
    #expect(e.profileDirectory(for: URL(string: "https://app.example.net/other")!) == "Profile 4")
}

@Test func wildcardWithoutSlashMatchesHostOnly() {
    let e = engine([Rule(matchType: .wildcard, pattern: "*.client-b.example.net", profileDirectory: "Profile 9")], default: "Profile 4")
    #expect(e.profileDirectory(for: URL(string: "https://foo.client-b.example.net/x/y")!) == "Profile 9")
}

@Test func wildcardWithSlashMatchesHostPath() {
    let e = engine([Rule(matchType: .wildcard, pattern: "*/sites/Docs*", profileDirectory: "Profile 6")], default: "Profile 4")
    #expect(e.profileDirectory(for: URL(string: "https://team.example.org/sites/Docs/Overview")!) == "Profile 6")
}

@Test func firstMatchWins() {
    let e = engine([
        Rule(matchType: .host, pattern: "example.com", profileDirectory: "Profile 10"),
        Rule(matchType: .host, pattern: "example.com", profileDirectory: "Profile 4"),
    ])
    #expect(e.profileDirectory(for: URL(string: "https://example.com")!) == "Profile 10")
}

@Test func noMatchFallsBackToDefault() {
    let e = engine([], default: "Profile 6")
    #expect(e.profileDirectory(for: URL(string: "https://unknown.example/x")!) == "Profile 6")
}

@Test func emptyPatternNeverMatches() {
    for t in MatchType.allCases {
        let e = engine([Rule(matchType: t, pattern: "", profileDirectory: "Profile 10")], default: "Profile 4")
        #expect(e.profileDirectory(for: URL(string: "https://anything.example/x")!) == "Profile 4")
    }
}
