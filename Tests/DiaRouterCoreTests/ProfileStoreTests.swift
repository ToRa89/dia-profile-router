// Tests/DiaRouterCoreTests/ProfileStoreTests.swift
import Testing
import Foundation
@testable import DiaRouterCore

private func fixture(_ name: String) -> URL {
    Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")!
}

@Test func loadsProfilesSortedByName() throws {
    let profiles = try ProfileStore.loadProfiles(localStatePath: fixture("LocalState"))
    #expect(profiles.contains(Profile(directory: "Profile 6", name: "Work")))
    #expect(profiles.contains(Profile(directory: "Profile 10", name: "Client A")))
    #expect(profiles.count == 3)
    // Sortierung nach Name: Client A, Personal, Work
    #expect(profiles.map(\.name) == ["Client A", "Personal", "Work"])
}
