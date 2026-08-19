// Tests/DiaRouterShellTests/DiaProfileAPITests.swift
import Testing
import Foundation
@testable import DiaRouterShell
import DiaRouterCore

// MARK: - Name resolution (position-independent)

@Test func resolvesProfileNameExactly() {
    let names = ["Reinholds", "Porsche", "Privat"]
    #expect(DiaProfileNames.resolve("Porsche", among: names) == "Porsche")
}

@Test func resolvesProfileNameIgnoringCaseWhitespaceAndUnicodeForm() {
    // "Büro" in decomposed form (NFD) must still match the composed (NFC) name Dia reports.
    let decomposed = "Bu\u{0308}ro"
    #expect(DiaProfileNames.resolve("  büro ", among: ["Reinholds", "Büro"]) == "Büro")
    #expect(DiaProfileNames.resolve(decomposed, among: ["Reinholds", "Büro"]) == "Büro")
}

@Test func doesNotResolveByPrefixOrPosition() {
    // A prefix must NOT match — that is how position-based confusion creeps back in.
    #expect(DiaProfileNames.resolve("Porsche", among: ["Por", "Privat"]) == nil)
    #expect(DiaProfileNames.resolve("Unbekannt", among: ["Reinholds", "Porsche"]) == nil)
}

// MARK: - Opening in the addressed profile

@Test @MainActor func opensTabInTargetProfileByNameWithoutSystemEvents() throws {
    let runner = FakeRunner()
    runner.windowProfilesResponse = "WIN-1<<|>>0<<|>>Reinholds<<|>>Reinholds<<;>>Porsche<<;>>Privat"

    let controller = DiaController(runner: runner)
    try controller.open(
        url: URL(string: "https://porsche.com/x")!,
        profileDirectory: "Profile 10",
        profiles: [Profile(directory: "Profile 10", name: "Porsche")]
    )

    // Tab is created in the *named* profile of that window …
    #expect(runner.scripts.contains {
        $0.contains("make new tab") && $0.contains("of profile \"Porsche\"") && $0.contains("WIN-1")
    })
    // … the neighbouring profile is never addressed …
    #expect(!runner.scripts.contains { $0.contains("of profile \"Privat\"") })
    // … and no UI scripting (System Events / Accessibility) is involved at all.
    #expect(!runner.scripts.contains { $0.contains("System Events") })
}

@Test @MainActor func prefersWindowWhereTargetProfileIsAlreadyActive() throws {
    let runner = FakeRunner()
    runner.windowProfilesResponse = """
    WIN-A<<|>>0<<|>>Reinholds<<|>>Reinholds<<;>>Porsche
    WIN-B<<|>>1<<|>>Porsche<<|>>Reinholds<<;>>Porsche
    """

    let controller = DiaController(runner: runner)
    try controller.open(
        url: URL(string: "https://porsche.com/x")!,
        profileDirectory: "Profile 10",
        profiles: [Profile(directory: "Profile 10", name: "Porsche")]
    )

    // WIN-B already shows Porsche → reuse it instead of switching the front window's profile.
    #expect(runner.scripts.contains { $0.contains("make new tab") && $0.contains("WIN-B") })
    #expect(!runner.scripts.contains { $0.contains("make new tab") && $0.contains("WIN-A") })
}

@Test @MainActor func usesFrontmostWindowWhenNoWindowShowsTargetProfile() throws {
    let runner = FakeRunner()
    // Deliberately unsorted: index 0 (front) comes last in the AppleScript output.
    runner.windowProfilesResponse = """
    WIN-BACK<<|>>2<<|>>Reinholds<<|>>Reinholds<<;>>Porsche
    WIN-FRONT<<|>>0<<|>>Reinholds<<|>>Reinholds<<;>>Porsche
    """

    let controller = DiaController(runner: runner)
    try controller.open(
        url: URL(string: "https://porsche.com/x")!,
        profileDirectory: "Profile 10",
        profiles: [Profile(directory: "Profile 10", name: "Porsche")]
    )

    #expect(runner.scripts.contains { $0.contains("make new tab") && $0.contains("WIN-FRONT") })
    #expect(!runner.scripts.contains { $0.contains("make new tab") && $0.contains("WIN-BACK") })
}

@Test @MainActor func ignoresStaleWindowCacheSoTabNeverLandsInNeighbourProfile() throws {
    let runner = FakeRunner()
    // The cached window is alive, but currently shows a DIFFERENT profile. Reusing it blindly
    // would drop the link into whatever profile happens to sit there (the reported bug).
    runner.windowListFallback = "WIN-1"
    runner.windowProfilesResponse = "WIN-1<<|>>0<<|>>Privat<<|>>Reinholds<<;>>Porsche<<;>>Privat"

    let controller = DiaController(runner: runner)
    controller.createdWindowCache["Profile 10"] = "WIN-1"

    try controller.open(
        url: URL(string: "https://porsche.com/x")!,
        profileDirectory: "Profile 10",
        profiles: [Profile(directory: "Profile 10", name: "Porsche")]
    )

    #expect(runner.scripts.contains { $0.contains("make new tab") && $0.contains("of profile \"Porsche\"") })
}

@Test @MainActor func fallsBackToLegacyMenuFlowWhenProfileAPIIsUnavailable() throws {
    let runner = FakeRunner()
    runner.windowProfilesResponse = ""            // older Dia: no profile elements
    runner.windowListQueue = ["WIN-1", "WIN-1", "WIN-1", "WIN-1\nNEW-WIN"]
    runner.submenuNamesResponse = "New Porsche Window\nNew Incognito Window"

    let controller = DiaController(runner: runner)
    try controller.open(
        url: URL(string: "https://porsche.com/x")!,
        profileDirectory: "Profile 10",
        profiles: [Profile(directory: "Profile 10", name: "Porsche")]
    )

    #expect(runner.scripts.contains { $0.contains("System Events") && $0.contains("New Porsche Window") })
    #expect(runner.scripts.contains { $0.contains("make new tab") && $0.contains("NEW-WIN") })
}

@Test @MainActor func fallsBackToFrontWindowWhenProfileIsNotOfferedByDia() throws {
    let runner = FakeRunner()
    // Dia knows profiles, but not the requested one (e.g. deleted in Dia, still in a rule).
    runner.windowProfilesResponse = "WIN-1<<|>>0<<|>>Reinholds<<|>>Reinholds<<;>>Privat"
    runner.windowListFallback = "WIN-1"
    runner.submenuNamesResponse = "New Incognito Window"

    let controller = DiaController(runner: runner)
    try controller.open(
        url: URL(string: "https://wolterskluwer.com/x")!,
        profileDirectory: "Profile 9",
        profiles: [Profile(directory: "Profile 9", name: "WoltersKluwer")]
    )

    // Never guess a neighbouring profile — land in the front window instead.
    #expect(!runner.scripts.contains { $0.contains("of profile ") })
    #expect(runner.scripts.contains { $0.contains("front window") })
}

@Test @MainActor func survivesMissingNewWindowSubmenuWithoutThrowing() throws {
    let runner = FakeRunner()
    // Reproduces the real failure: current Dia has no File → New Window submenu at all,
    // so the Accessibility query throws. That must not escalate into a routing failure.
    runner.windowProfilesResponse = ""
    runner.windowListFallback = "WIN-1"
    runner.submenuNamesThrows = true

    let controller = DiaController(runner: runner)
    try controller.open(
        url: URL(string: "https://porsche.com/x")!,
        profileDirectory: "Profile 10",
        profiles: [Profile(directory: "Profile 10", name: "Porsche")]
    )

    #expect(runner.scripts.contains { $0.contains("front window") })
}
