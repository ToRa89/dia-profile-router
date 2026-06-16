// Tests/DiaRouterCoreTests/ModelsTests.swift
import Testing
import Foundation
@testable import DiaRouterCore

@Test func ruleConfigRoundTripsThroughJSON() throws {
    let config = RouterConfig(
        rules: [Rule(matchType: .host, pattern: "example.com", profileDirectory: "Profile 10")],
        defaultProfileDirectory: "Profile 6"
    )
    let data = try JSONEncoder().encode(config)
    let decoded = try JSONDecoder().decode(RouterConfig.self, from: data)
    #expect(decoded == config)
}

@Test func profileIdEqualsDirectory() {
    let p = Profile(directory: "Profile 6", name: "Work")
    #expect(p.id == "Profile 6")
}
