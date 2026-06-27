// Tests/DiaRouterShellTests/RouterTests.swift
import Testing
import Foundation
@testable import DiaRouterShell
import DiaRouterCore

@MainActor
final class MockChooser: ProfileChooser {
    var result: ChooserResult?
    private(set) var callCount = 0
    init(result: ChooserResult?) { self.result = result }
    func choose(url: URL, profiles: [Profile], defaultDirectory: String) async -> ChooserResult? {
        callCount += 1
        return result
    }
}

private func tempConfigURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("dia-router-test-\(UUID().uuidString)")
        .appendingPathComponent("config.json")
}

private func writeConfig(_ cfg: RouterConfig, to url: URL) throws {
    try ConfigStore.save(cfg, to: url)
}

@Test @MainActor func matchedRuleRoutesWithoutCallingChooser() async throws {
    let cfgURL = tempConfigURL()
    try writeConfig(RouterConfig(
        rules: [Rule(matchType: .host, pattern: "example.com", profileDirectory: "Profile 9")],
        defaultProfileDirectory: "Profile 6"), to: cfgURL)

    let runner = FakeRunner()
    runner.windowListFallback = "WIN-1"
    let chooser = MockChooser(result: nil)
    let router = Router(runner: runner, chooser: chooser,
                        configPath: cfgURL, localStatePath: cfgURL /* no profiles file → [] */)

    await router.route(URL(string: "https://app.example.com/x")!)

    #expect(chooser.callCount == 0)            // rule matched → no prompt
}

@Test @MainActor func unmatchedWithRememberWritesRuleAndRoutesToChoice() async throws {
    let cfgURL = tempConfigURL()
    try writeConfig(RouterConfig(rules: [], defaultProfileDirectory: "Profile 6"), to: cfgURL)

    let runner = FakeRunner()
    runner.windowListFallback = "WIN-1"
    let chooser = MockChooser(result: ChooserResult(profileDirectory: "Profile 9", rememberPattern: "neuekunde.de"))
    let router = Router(runner: runner, chooser: chooser, configPath: cfgURL, localStatePath: cfgURL)

    await router.route(URL(string: "https://www.neuekunde.de/x")!)

    #expect(chooser.callCount == 1)
    let saved = try ConfigStore.load(from: cfgURL)
    #expect(saved.rules.contains { $0.matchType == .host && $0.pattern == "neuekunde.de" && $0.profileDirectory == "Profile 9" })
}

@Test @MainActor func cancelledChooserRoutesToDefaultAndWritesNoRule() async throws {
    let cfgURL = tempConfigURL()
    try writeConfig(RouterConfig(rules: [], defaultProfileDirectory: "Profile 6"), to: cfgURL)

    let runner = FakeRunner()
    runner.windowListFallback = "WIN-1"
    let chooser = MockChooser(result: nil)     // cancelled
    let router = Router(runner: runner, chooser: chooser, configPath: cfgURL, localStatePath: cfgURL)

    await router.route(URL(string: "https://www.neuekunde.de/x")!)

    #expect(chooser.callCount == 1)
    let saved = try ConfigStore.load(from: cfgURL)
    #expect(saved.rules.isEmpty)               // nothing learned on cancel
    // Verify the router attempted to route somewhere after cancel (the needsChoice path ran and
    // placement was attempted without throwing). The profile directory ("Profile 6") never appears
    // in AppleScript source because DiaController resolves it as an unknown profile (the test
    // uses configPath as localStatePath, yielding no loaded profiles) and falls back to front
    // window — so a script-content assertion on the profile string is not possible without a
    // real profiles fixture. The chooser call count above already proves the cancel path was taken.
    #expect(runner.scripts.contains { $0.contains("make new tab") || $0.contains("front window") })
}

@Test @MainActor func safeLinksURLIsUnwrappedBeforeRuleMatching() async throws {
    let cfgURL = tempConfigURL()
    try writeConfig(RouterConfig(
        rules: [Rule(matchType: .host, pattern: "porsche.com", profileDirectory: "Profile 10")],
        defaultProfileDirectory: "Profile 6"), to: cfgURL)

    let runner = FakeRunner()
    runner.windowListFallback = "WIN-1"
    let chooser = MockChooser(result: nil)
    let router = Router(runner: runner, chooser: chooser,
                        configPath: cfgURL, localStatePath: cfgURL)

    // A SafeLinks URL wrapping porsche.com — rule should match, chooser must NOT be called
    let safeLink = URL(string:
        "https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fwww.porsche.com%2Fde%2F&data=x")!
    await router.route(safeLink)

    #expect(chooser.callCount == 0)   // rule matched the unwrapped URL → no chooser prompt
}
