// Tests/DiaRouterShellTests/DiaControllerTests.swift
import Testing
import Foundation
@testable import DiaRouterShell
import DiaRouterCore

/// A fake runner that returns configurable responses per script content.
/// For window-list queries it pops from a FIFO queue so successive calls can
/// return different values (simulating the pre/post-click state).
final class FakeRunner: AppleScriptRunning, @unchecked Sendable {
    var scripts: [String] = []

    /// Queue of responses for "id of every window" calls. If empty, falls back to windowListFallback.
    var windowListQueue: [String] = []
    /// Fallback when windowListQueue is exhausted.
    var windowListFallback: String = ""

    /// Response for submenu-names queries.
    var submenuNamesResponse: String = ""

    /// Response for the active-tab-per-window query ("uuid<<|>>URL" lines).
    var activeURLsResponse: String = ""

    /// Response for the all-tabs-per-window query ("uuid<<|>>URL" lines, one per tab).
    var allTabsResponse: String = ""

    func run(_ source: String) throws -> String {
        scripts.append(source)
        if source.contains("ALLTABS") {
            return allTabsResponse
        }
        if source.contains("active tab") {
            return activeURLsResponse
        }
        if source.contains("id of every window") {
            if !windowListQueue.isEmpty {
                return windowListQueue.removeFirst()
            }
            return windowListFallback
        }
        if source.contains("every menu item of menu") {
            return submenuNamesResponse
        }
        // click / make new tab → return empty, just record
        return ""
    }
}

@Test @MainActor func reusesCachedWindowWhenAlive() throws {
    let runner = FakeRunner()
    // The cached window UUID is still alive
    runner.windowListFallback = "7CD17B72-0000-0000-0000-000000000001"

    let controller = DiaController(runner: runner)
    // Manually seed cache
    controller.createdWindowCache["Profile 10"] = "7CD17B72-0000-0000-0000-000000000001"

    let profiles = [Profile(directory: "Profile 10", name: "Client A")]
    try controller.open(
        url: URL(string: "https://example.com")!,
        profileDirectory: "Profile 10",
        profiles: profiles
    )

    // Should produce a "make new tab" script containing the cached UUID
    #expect(runner.scripts.contains {
        $0.contains("make new tab") && $0.contains("7CD17B72-0000-0000-0000-000000000001")
    })
    // No System Events (no new window needed)
    #expect(!runner.scripts.contains { $0.contains("System Events") && $0.contains("click") })
}

@Test @MainActor func reusesOpenWindowWhoseActiveTabMatchesProfile() throws {
    let runner = FakeRunner()
    runner.windowListFallback = "WIN-A\nWIN-B"
    // WIN-B's active tab routes to the target profile; WIN-A does not.
    // Delimiter matches DiaController.windowsWithActiveURLs ("<<|>>").
    runner.activeURLsResponse = "WIN-A<<|>>https://other.example.io/x\nWIN-B<<|>>https://app.example.com/jira"

    let controller = DiaController(runner: runner)
    let profiles = [Profile(directory: "Profile 10", name: "Client A")]
    try controller.open(
        url: URL(string: "https://app.example.com/new")!,
        profileDirectory: "Profile 10",
        profiles: profiles,
        belongsToTargetProfile: { $0.host?.hasSuffix("example.com") == true }
    )

    // Reuses WIN-B as a tab; no new window (no System Events) is created.
    #expect(runner.scripts.contains { $0.contains("make new tab") && $0.contains("WIN-B") })
    #expect(!runner.scripts.contains { $0.contains("System Events") })
    #expect(controller.createdWindowCache["Profile 10"] == "WIN-B")
}

@Test @MainActor func reusesWindowWhenOnlyANonActiveTabMatches() throws {
    let runner = FakeRunner()
    runner.windowListFallback = "WIN-A\nWIN-B"
    // No window's ACTIVE tab matches the target profile...
    runner.activeURLsResponse = "WIN-A<<|>>https://other.example.io/x\nWIN-B<<|>>https://google.com"
    // ...but WIN-B has a non-active tab that does.
    runner.allTabsResponse = """
    WIN-A<<|>>https://other.example.io/x
    WIN-B<<|>>https://google.com
    WIN-B<<|>>https://app.example.com/jira
    """

    let controller = DiaController(runner: runner)
    let profiles = [Profile(directory: "Profile 10", name: "Client A")]
    try controller.open(
        url: URL(string: "https://app.example.com/new")!,
        profileDirectory: "Profile 10",
        profiles: profiles,
        belongsToTargetProfile: { $0.host?.hasSuffix("example.com") == true }
    )

    #expect(runner.scripts.contains { $0.contains("make new tab") && $0.contains("WIN-B") })
    #expect(!runner.scripts.contains { $0.contains("System Events") })
    #expect(controller.createdWindowCache["Profile 10"] == "WIN-B")
}

@Test @MainActor func createsNewWindowWhenNotCached() throws {
    let runner = FakeRunner()
    // First window-list call (liveWindowUUIDs at top of open): old UUID only
    runner.windowListQueue = [
        "OLD-UUID-0000-0000-0000-000000000001",                       // initial live check
        "OLD-UUID-0000-0000-0000-000000000001",                       // pre-click snapshot
        // poll iterations: first try still no new window, second try has new window
        "OLD-UUID-0000-0000-0000-000000000001",
        "OLD-UUID-0000-0000-0000-000000000001\nNEW-UUID-1111-0000-0000-0000-000000000002",
    ]
    runner.submenuNamesResponse = "New Community Window\nNew Client A Window\nmissing value\nNew Incognito Window"

    let controller = DiaController(runner: runner)
    let profiles = [Profile(directory: "Profile 10", name: "Client A")]
    try controller.open(
        url: URL(string: "https://example.com")!,
        profileDirectory: "Profile 10",
        profiles: profiles
    )

    // A System Events click script containing "New Client A Window" should have been produced
    #expect(runner.scripts.contains {
        $0.contains("System Events") && $0.contains("New Client A Window")
    })
    // A "make new tab" script should reference the NEW window UUID
    #expect(runner.scripts.contains {
        $0.contains("make new tab") && $0.contains("NEW-UUID-1111-0000-0000-0000-000000000002")
    })
    // Cache should be updated
    #expect(controller.createdWindowCache["Profile 10"] == "NEW-UUID-1111-0000-0000-0000-000000000002")
}

@Test @MainActor func fallsBackToFrontWindowWhenNoMatchingMenuItem() throws {
    let runner = FakeRunner()
    // The window list is non-empty so we don't short-circuit on an empty list
    runner.windowListFallback = "SOME-UUID-0000-0000-0000-000000000001"
    // Submenu contains only non-matching entries — no item for "Client A"
    runner.submenuNamesResponse = "New Incognito Window\nmissing value"

    let controller = DiaController(runner: runner)
    // Profile IS known
    let profiles = [Profile(directory: "Profile 10", name: "Client A")]
    try controller.open(
        url: URL(string: "https://example.com")!,
        profileDirectory: "Profile 10",
        profiles: profiles
    )

    // Should fall back to front window
    #expect(runner.scripts.contains { $0.contains("front window") })
    // No System Events click of a New Window menu item should have been issued
    #expect(!runner.scripts.contains { $0.contains("System Events") && $0.contains("click") })
}

@Test @MainActor func fallsBackToFrontWindowWhenProfileUnknown() throws {
    let runner = FakeRunner()
    runner.windowListFallback = "SOME-UUID-0000-0000-0000-000000000001"

    let controller = DiaController(runner: runner)
    // Pass empty profiles list so the directory can't be resolved
    try controller.open(
        url: URL(string: "https://example.com")!,
        profileDirectory: "Profile 10",
        profiles: []
    )

    // Should open in front window and NOT touch System Events
    #expect(runner.scripts.contains { $0.contains("front window") })
    #expect(!runner.scripts.contains { $0.contains("System Events") && $0.contains("click") })
}
