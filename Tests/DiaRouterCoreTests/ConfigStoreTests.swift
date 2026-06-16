// Tests/DiaRouterCoreTests/ConfigStoreTests.swift
import Testing
import Foundation
@testable import DiaRouterCore

@Test func savesAndLoadsConfigRoundTrip() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathComponent("config.json")
    let config = RouterConfig(
        rules: [Rule(matchType: .wildcard, pattern: "*.example.com", profileDirectory: "Profile 10")],
        defaultProfileDirectory: "Profile 6"
    )
    try ConfigStore.save(config, to: tmp)
    let loaded = try ConfigStore.load(from: tmp)
    #expect(loaded == config)
}

@Test func loadReturnsDefaultWhenFileMissing() throws {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
    let loaded = try ConfigStore.loadOrDefault(from: missing, defaultProfileDirectory: "Profile 6")
    #expect(loaded.rules.isEmpty)
    #expect(loaded.defaultProfileDirectory == "Profile 6")
}
