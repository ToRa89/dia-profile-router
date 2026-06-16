// Tests/DiaRouterCoreTests/WildcardTests.swift
import Testing
@testable import DiaRouterCore

@Test func starMatchesAnySubdomain() {
    #expect(Wildcard.matches(pattern: "*.example.com", value: "app.example.com"))
    #expect(Wildcard.matches(pattern: "*.example.com", value: "a.b.example.com"))
}

@Test func starDoesNotCrossUnintendedBoundariesWhenLiteral() {
    #expect(!Wildcard.matches(pattern: "*.example.com", value: "example.com.evil.com"))
}

@Test func middleStarMatchesPath() {
    #expect(Wildcard.matches(pattern: "*/sites/Docs*", value: "team.example.org/sites/Docs/Overview"))
}

@Test func literalSpecialCharsAreEscaped() {
    #expect(Wildcard.matches(pattern: "a.b", value: "a.b"))
    #expect(!Wildcard.matches(pattern: "a.b", value: "axb"))
}

@Test func emptyStarMatchesEmpty() {
    #expect(Wildcard.matches(pattern: "*", value: ""))
    #expect(Wildcard.matches(pattern: "*", value: "anything/here"))
}
