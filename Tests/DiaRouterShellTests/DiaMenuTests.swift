// Tests/DiaRouterShellTests/DiaMenuTests.swift
import Testing
@testable import DiaRouterShell

@Test func exactMatchReturnsItem() {
    let items = ["New Client A Window", "New Work Window", "New Incognito Window"]
    let result = DiaMenu.newWindowMenuItem(forProfileName: "Client A", among: items)
    #expect(result == "New Client A Window")
}

@Test func truncatedMatchReturnsTruncatedItem() {
    // Profile "Home Automation" → menu shows "New Home Automati… Window"
    let items = ["New Client A Window", "New Home Automati… Window", "New Incognito Window"]
    let result = DiaMenu.newWindowMenuItem(forProfileName: "Home Automation", among: items)
    #expect(result == "New Home Automati… Window")
}

@Test func incognitoItemNotMatchedForRealProfile() {
    // "New Incognito Window" should not match a profile named e.g. "Client A"
    let items = ["New Incognito Window"]
    let result = DiaMenu.newWindowMenuItem(forProfileName: "Client A", among: items)
    #expect(result == nil)
}

@Test func noMatchReturnsNil() {
    let items = ["New Client A Window", "New Incognito Window"]
    let result = DiaMenu.newWindowMenuItem(forProfileName: "Community", among: items)
    #expect(result == nil)
}

@Test func shortProfileNameDoesNotMatchLongerMenuCore() {
    // Profile "Wo" should NOT match menu item "New Work Window" (core "Work")
    // because "wo".hasPrefix("work") is false
    let items = ["New Work Window"]
    let result = DiaMenu.newWindowMenuItem(forProfileName: "Wo", among: items)
    #expect(result == nil)
}

@Test func caseInsensitiveExactMatch() {
    let items = ["New Community Window"]
    let result = DiaMenu.newWindowMenuItem(forProfileName: "community", among: items)
    #expect(result == "New Community Window")
}

@Test func emptyItemsListReturnsNil() {
    let result = DiaMenu.newWindowMenuItem(forProfileName: "Client A", among: [])
    #expect(result == nil)
}
