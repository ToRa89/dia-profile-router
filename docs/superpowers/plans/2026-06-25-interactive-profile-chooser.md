# Interactive Profile Chooser + Rule Learning — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When no rule matches an incoming link, prompt the user for the target Dia profile (optionally learning a host rule), and place links only via reliable window signals instead of guessing.

**Architecture:** Pure decision/rule logic in `DiaRouterCore` (unit-tested, no UI). `DiaRouterShell` orchestrates routing and talks AppleScript; the chooser is an injected `ProfileChooser` protocol. `DiaProfileRouterApp` supplies the concrete AppKit chooser window. The unreliable "any tab matches" window-reuse heuristic is removed; a decision logger makes future regressions diagnosable in one `log show` query.

**Tech Stack:** Swift 6, Swift Package Manager, Swift Testing (`import Testing`), AppKit + SwiftUI, `os.Logger`, AppleScript via `NSAppleScript`.

## Global Constraints

- Platform floor: macOS 13 (`.macOS(.v13)`), `LSUIElement` menu-bar app.
- Swift 6 strict concurrency; UI/routing types are `@MainActor`; data crossing boundaries is `Sendable`.
- `DiaRouterCore` must NOT import AppKit/SwiftUI (stays pure & portable).
- Tests use Swift Testing (`@Test`, `#expect`), one fresh instance per test.
- Logger subsystem is exactly `com.tora89.dia-profile-router`, category `routing`.
- Remembered rules use `matchType .host`, pattern = host without leading `www.`; never collapse to a registrable domain (keep `porsche.sharepoint.com` whole).
- Commit messages: Conventional Commits. Do NOT add Co-Authored-By/attribution (disabled globally by the user).
- Work happens on branch `feat/profile-chooser` (already created; the design spec is committed there).

---

### Task 1: RouteDecision + `RuleEngine.decide` (Core)

**Files:**
- Create: `Sources/DiaRouterCore/RouteDecision.swift`
- Test: `Tests/DiaRouterCoreTests/RouteDecisionTests.swift`

**Interfaces:**
- Consumes: `RuleEngine` (existing), `URLNormalize.host` (existing).
- Produces: `enum RouteDecision { case matched(profileDirectory: String); case needsChoice(host: String) }`; `RuleEngine.decide(for: URL) -> RouteDecision`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/DiaRouterCoreTests/RouteDecisionTests.swift
import Testing
import Foundation
@testable import DiaRouterCore

@Test func decideReturnsMatchedWhenRuleMatches() {
    let cfg = RouterConfig(
        rules: [Rule(matchType: .host, pattern: "example.com", profileDirectory: "Profile 9")],
        defaultProfileDirectory: "Profile 6")
    let engine = RuleEngine(config: cfg)
    #expect(engine.decide(for: URL(string: "https://app.example.com/x")!)
            == .matched(profileDirectory: "Profile 9"))
}

@Test func decideReturnsNeedsChoiceWithHostWhenNoRuleMatches() {
    let engine = RuleEngine(config: RouterConfig(rules: [], defaultProfileDirectory: "Profile 6"))
    #expect(engine.decide(for: URL(string: "https://www.unknown.test/abc")!)
            == .needsChoice(host: "www.unknown.test"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter decideReturns`
Expected: FAIL — `value of type 'RuleEngine' has no member 'decide'`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/DiaRouterCore/RouteDecision.swift
import Foundation

/// Outcome of evaluating routing rules for a URL.
public enum RouteDecision: Equatable, Sendable {
    /// A rule matched → route directly to this profile directory.
    case matched(profileDirectory: String)
    /// No rule matched → ask the user. `host` is the normalized host (for prompt + rule suggestion).
    case needsChoice(host: String)
}

extension RuleEngine {
    /// Decide how to route a URL: a matched rule, or that a prompt is needed.
    public func decide(for url: URL) -> RouteDecision {
        if let rule = matchedRule(for: url) {
            return .matched(profileDirectory: rule.profileDirectory)
        }
        return .needsChoice(host: URLNormalize.host(url))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter decideReturns`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DiaRouterCore/RouteDecision.swift Tests/DiaRouterCoreTests/RouteDecisionTests.swift
git commit -m "feat(core): add RouteDecision and RuleEngine.decide"
```

---

### Task 2: RuleSuggestion (Core)

**Files:**
- Create: `Sources/DiaRouterCore/RuleSuggestion.swift`
- Test: `Tests/DiaRouterCoreTests/RuleSuggestionTests.swift`

**Interfaces:**
- Consumes: `URLNormalize.host`, `Rule`, `RouterConfig`, `MatchType` (all existing).
- Produces: `RuleSuggestion.hostPattern(for: URL) -> String?`; `RuleSuggestion.appended(_ rule: Rule, to: RouterConfig) -> RouterConfig`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/DiaRouterCoreTests/RuleSuggestionTests.swift
import Testing
import Foundation
@testable import DiaRouterCore

@Test func hostPatternStripsLeadingWWWAndLowercases() {
    #expect(RuleSuggestion.hostPattern(for: URL(string: "https://WWW.NeueKunde.de/angebot")!) == "neuekunde.de")
}

@Test func hostPatternKeepsMultiTenantSubdomain() {
    #expect(RuleSuggestion.hostPattern(for: URL(string: "https://porsche.sharepoint.com/sites/x")!)
            == "porsche.sharepoint.com")
}

@Test func hostPatternIsNilWhenNoHost() {
    #expect(RuleSuggestion.hostPattern(for: URL(string: "file:///tmp/x")!) == nil)
}

@Test func appendedAddsNewRule() {
    let cfg = RouterConfig(rules: [], defaultProfileDirectory: "Profile 6")
    let out = RuleSuggestion.appended(
        Rule(matchType: .host, pattern: "neuekunde.de", profileDirectory: "Profile 9"), to: cfg)
    #expect(out.rules.count == 1)
    #expect(out.rules[0].pattern == "neuekunde.de")
    #expect(out.rules[0].profileDirectory == "Profile 9")
}

@Test func appendedUpdatesProfileForExistingHostPattern() {
    let cfg = RouterConfig(
        rules: [Rule(matchType: .host, pattern: "neuekunde.de", profileDirectory: "Profile 6")],
        defaultProfileDirectory: "Profile 6")
    let out = RuleSuggestion.appended(
        Rule(matchType: .host, pattern: "NeueKunde.de", profileDirectory: "Profile 9"), to: cfg)
    #expect(out.rules.count == 1)                       // no duplicate
    #expect(out.rules[0].profileDirectory == "Profile 9")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "hostPattern"`
Expected: FAIL — `cannot find 'RuleSuggestion' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/DiaRouterCore/RuleSuggestion.swift
import Foundation

/// Helpers for turning a chooser decision into a persisted rule.
public enum RuleSuggestion {
    /// Default host pattern for "remember this site": lowercased host without a leading "www.".
    /// Returns nil when there is no host. Deliberately does NOT collapse to a registrable
    /// domain — that would merge distinct tenants like `porsche.sharepoint.com`.
    public static func hostPattern(for url: URL) -> String? {
        let h = URLNormalize.host(url)
        guard !h.isEmpty else { return nil }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    /// Returns a new config with `rule` applied: if a `.host` rule with the same pattern
    /// (case-insensitive) exists, its profile is updated; otherwise the rule is appended.
    public static func appended(_ rule: Rule, to config: RouterConfig) -> RouterConfig {
        var result = config
        let pat = rule.pattern.lowercased()
        if let idx = result.rules.firstIndex(where: {
            $0.matchType == .host && $0.pattern.lowercased() == pat
        }) {
            result.rules[idx].profileDirectory = rule.profileDirectory
        } else {
            result.rules.append(rule)
        }
        return result
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter "hostPattern" && swift test --filter "appended"`
Expected: PASS (5 tests total).

- [ ] **Step 5: Commit**

```bash
git add Sources/DiaRouterCore/RuleSuggestion.swift Tests/DiaRouterCoreTests/RuleSuggestionTests.swift
git commit -m "feat(core): add RuleSuggestion (host pattern + append/dedup)"
```

---

### Task 3: Remove unreliable any-tab reuse + add routing logger (Shell)

**Files:**
- Create: `Sources/DiaRouterShell/RoutingLog.swift`
- Modify: `Sources/DiaRouterShell/DiaController.swift` (remove all-tabs block + `windowsWithAllTabURLs()`; add logging)
- Test: `Tests/DiaRouterShellTests/DiaControllerTests.swift` (rewrite the non-active-tab test)

**Interfaces:**
- Produces: `RoutingLog.logger` (`os.Logger`). `DiaController.open` behavior change: no any-tab reuse.
- Consumes: existing `DiaController` internals.

- [ ] **Step 1: Rewrite the affected test to the new expectation**

Replace the existing `reusesWindowWhenOnlyANonActiveTabMatches` test (DiaControllerTests.swift:95-119) with:

```swift
@Test @MainActor func createsNewWindowWhenOnlyNonActiveTabMatches() throws {
    let runner = FakeRunner()
    // liveWindowUUIDs: initial, pre-click snapshot, poll(no), poll(new)
    runner.windowListQueue = [
        "WIN-A\nWIN-B",
        "WIN-A\nWIN-B",
        "WIN-A\nWIN-B",
        "WIN-A\nWIN-B\nNEW-WIN",
    ]
    // No window's ACTIVE tab matches the target profile...
    runner.activeURLsResponse = "WIN-A<<|>>https://other.example.io/x\nWIN-B<<|>>https://google.com"
    // ...even though WIN-B has a background tab that would (must be IGNORED now).
    runner.allTabsResponse = "WIN-B<<|>>https://app.example.com/jira"
    runner.submenuNamesResponse = "New Community Window\nNew Client A Window\nNew Incognito Window"

    let controller = DiaController(runner: runner)
    let profiles = [Profile(directory: "Profile 10", name: "Client A")]
    try controller.open(
        url: URL(string: "https://app.example.com/new")!,
        profileDirectory: "Profile 10",
        profiles: profiles,
        belongsToTargetProfile: { $0.host?.hasSuffix("example.com") == true }
    )

    // A NEW window is created via System Events; the background-tab window is NOT reused.
    #expect(runner.scripts.contains { $0.contains("System Events") && $0.contains("New Client A Window") })
    #expect(runner.scripts.contains { $0.contains("make new tab") && $0.contains("NEW-WIN") })
    #expect(!runner.scripts.contains { $0.contains("make new tab") && $0.contains("WIN-B") })
    #expect(controller.createdWindowCache["Profile 10"] == "NEW-WIN")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter createsNewWindowWhenOnlyNonActiveTabMatches`
Expected: FAIL — current code reuses WIN-B (the `make new tab ... WIN-B` assertion's negation fails), proving the 2c path still runs.

- [ ] **Step 3: Add the logger**

```swift
// Sources/DiaRouterShell/RoutingLog.swift
import Foundation
import os

/// Central logger for routing decisions. Query with:
///   log show --predicate 'subsystem == "com.tora89.dia-profile-router"' --info
public enum RoutingLog {
    public static let logger = Logger(subsystem: "com.tora89.dia-profile-router", category: "routing")
}
```

- [ ] **Step 4: Remove the any-tab heuristic and add per-branch logging**

In `Sources/DiaRouterShell/DiaController.swift`, delete the entire block at lines 43–51 (the comment `// 2c. Fallback heuristic...` through its closing `}`), and delete the whole `windowsWithAllTabURLs()` method (lines 127–163). Then add logging so `open(...)` reads:

```swift
public func open(
    url: URL,
    profileDirectory: String,
    profiles: [Profile],
    belongsToTargetProfile: (URL) -> Bool = { _ in false }
) throws {
    let live = try liveWindowUUIDs()

    // 1. Cache hit: reuse the window we previously opened/confirmed for this profile if still alive
    if let cached = createdWindowCache[profileDirectory], live.contains(cached) {
        RoutingLog.logger.info("place \(profileDirectory, privacy: .public) -> cache \(cached, privacy: .public)")
        try openTab(url: url, inWindow: cached)
        return
    }

    // 2. ACTIVE TAB WINS — reuse a window whose *active* tab routes (by the user's rules) to this
    //    profile. Strongest signal, lowest ambiguity. (The unreliable "any tab" pass was removed.)
    let activeTabs = try windowsWithActiveURLs()
    if let match = activeTabs.first(where: { $0.url.map(belongsToTargetProfile) ?? false }) {
        createdWindowCache[profileDirectory] = match.uuid
        RoutingLog.logger.info("place \(profileDirectory, privacy: .public) -> activeTab \(match.uuid, privacy: .public)")
        try openTab(url: url, inWindow: match.uuid)
        return
    }

    // 3. Resolve display name for the target profile
    guard let profileName = profiles.first(where: { $0.directory == profileDirectory })?.name else {
        RoutingLog.logger.info("place \(profileDirectory, privacy: .public) -> frontFallback (unknown profile)")
        try openTabInFrontWindow(url: url)
        return
    }

    // 4. Resolve the exact menu item name (handles truncation)
    let submenuItems = try newWindowSubmenuItemNames()
    guard let menuItemName = DiaMenu.newWindowMenuItem(forProfileName: profileName, among: submenuItems) else {
        RoutingLog.logger.info("place \(profileDirectory, privacy: .public) -> frontFallback (no menu item)")
        try openTabInFrontWindow(url: url)
        return
    }

    // 5. Click menu item, poll for the new window
    let preClickUUIDs = Set(try liveWindowUUIDs())
    try clickNewWindowItem(menuItemName)
    if let newUUID = try pollForNewWindow(preClickUUIDs: preClickUUIDs) {
        createdWindowCache[profileDirectory] = newUUID
        RoutingLog.logger.info("place \(profileDirectory, privacy: .public) -> newWindow \(newUUID, privacy: .public) via \(menuItemName, privacy: .public)")
        try openTab(url: url, inWindow: newUUID)
    } else {
        RoutingLog.logger.info("place \(profileDirectory, privacy: .public) -> frontFallback (poll timeout)")
        try openTabInFrontWindow(url: url)
    }
}
```

Leave `FakeRunner.allTabsResponse` and its `if source.contains("ALLTABS")` branch in the test file as-is (now unused by production; harmless and keeps the new test's `allTabsResponse` setter compiling).

- [ ] **Step 5: Run tests to verify pass + nothing regressed**

Run: `swift test --filter DiaControllerTests`
Expected: PASS (all DiaController tests, including the new `createsNewWindowWhenOnlyNonActiveTabMatches`).

- [ ] **Step 6: Commit**

```bash
git add Sources/DiaRouterShell/RoutingLog.swift Sources/DiaRouterShell/DiaController.swift Tests/DiaRouterShellTests/DiaControllerTests.swift
git commit -m "fix(shell): drop unreliable any-tab window reuse; add routing logger"
```

---

### Task 4: ProfileChooser protocol + async Router with rule learning (Shell)

**Files:**
- Create: `Sources/DiaRouterShell/ProfileChooser.swift`
- Modify: `Sources/DiaRouterShell/Router.swift` (async route, injected chooser, rule learning, logging, injectable paths)
- Test: `Tests/DiaRouterShellTests/RouterTests.swift`

**Interfaces:**
- Consumes: `RuleEngine.decide` (Task 1), `RuleSuggestion.appended` (Task 2), `RoutingLog` (Task 3), existing `DiaController`, `ConfigStore`, `ProfileStore`, `AppleScriptRunning`.
- Produces:
  - `struct ChooserResult { let profileDirectory: String; let rememberPattern: String? }` (Equatable, Sendable).
  - `@MainActor protocol ProfileChooser { func choose(url: URL, profiles: [Profile], defaultDirectory: String) async -> ChooserResult? }`.
  - `Router.init(runner:chooser:configPath:localStatePath:)`; `func route(_ url: URL) async`.

- [ ] **Step 1: Write the failing tests**

```swift
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter RouterTests`
Expected: FAIL — `Router` has no `chooser:` initializer / `route` is not `async` / `ProfileChooser` undefined.

- [ ] **Step 3: Create the ProfileChooser protocol + result**

```swift
// Sources/DiaRouterShell/ProfileChooser.swift
import Foundation
import DiaRouterCore

/// The user's decision from the profile chooser.
public struct ChooserResult: Equatable, Sendable {
    /// Chosen profile directory (e.g. "Profile 9").
    public let profileDirectory: String
    /// Host pattern to remember as a new `.host` rule, or nil to not create a rule.
    public let rememberPattern: String?
    public init(profileDirectory: String, rememberPattern: String?) {
        self.profileDirectory = profileDirectory
        self.rememberPattern = rememberPattern
    }
}

/// Presents a profile chooser to the user. Production shows a window; tests inject a mock.
/// Returns nil when the user cancels.
@MainActor
public protocol ProfileChooser {
    func choose(url: URL, profiles: [Profile], defaultDirectory: String) async -> ChooserResult?
}
```

- [ ] **Step 4: Rewrite Router**

```swift
// Sources/DiaRouterShell/Router.swift
import AppKit
import DiaRouterCore

/// Binds config, profiles, the chooser, and the DiaController together.
@MainActor
public final class Router {
    private let controller: DiaController
    private let chooser: any ProfileChooser
    private let configPath: URL
    private let localStatePath: URL

    public init(
        runner: any AppleScriptRunning = NSAppleScriptRunner(),
        chooser: any ProfileChooser,
        configPath: URL = ConfigStore.defaultPath(),
        localStatePath: URL = ProfileStore.defaultLocalStatePath()
    ) {
        self.controller = DiaController(runner: runner)
        self.chooser = chooser
        self.configPath = configPath
        self.localStatePath = localStatePath
    }

    public func route(_ url: URL) async {
        let config = loadConfig()
        let profiles = (try? ProfileStore.loadProfiles(localStatePath: localStatePath)) ?? []
        let engine = RuleEngine(config: config)

        switch engine.decide(for: url) {
        case .matched(let dir):
            RoutingLog.logger.info("route \(url.absoluteString, privacy: .public) -> \(dir, privacy: .public) [rule]")
            place(url, profileDirectory: dir, engine: engine, profiles: profiles)

        case .needsChoice(let host):
            RoutingLog.logger.info("route \(url.absoluteString, privacy: .public) -> needsChoice host=\(host, privacy: .public)")
            guard let result = await chooser.choose(
                url: url, profiles: profiles, defaultDirectory: config.defaultProfileDirectory) else {
                RoutingLog.logger.info("chooser cancelled -> default \(config.defaultProfileDirectory, privacy: .public)")
                place(url, profileDirectory: config.defaultProfileDirectory, engine: engine, profiles: profiles)
                return
            }
            if let pattern = result.rememberPattern, !pattern.isEmpty {
                rememberRule(pattern: pattern, profileDirectory: result.profileDirectory)
            }
            RoutingLog.logger.info("chooser -> \(result.profileDirectory, privacy: .public) remember=\(result.rememberPattern ?? "-", privacy: .public)")
            place(url, profileDirectory: result.profileDirectory, engine: engine, profiles: profiles)
        }
    }

    private func loadConfig() -> RouterConfig {
        (try? ConfigStore.loadOrDefault(from: configPath, defaultProfileDirectory: "Default"))
            ?? RouterConfig(rules: [], defaultProfileDirectory: "Default")
    }

    /// Append/update a `.host` rule, reading config FRESH right before writing — avoids lost
    /// updates when several needsChoice links resolve one after another.
    private func rememberRule(pattern: String, profileDirectory: String) {
        let updated = RuleSuggestion.appended(
            Rule(matchType: .host, pattern: pattern, profileDirectory: profileDirectory),
            to: loadConfig())
        do { try ConfigStore.save(updated, to: configPath) }
        catch { RoutingLog.logger.error("rule save failed: \(String(describing: error), privacy: .public)") }
    }

    private func place(_ url: URL, profileDirectory: String, engine: RuleEngine, profiles: [Profile]) {
        // A window belongs to the target only if its active tab EXPLICITLY matches a rule for it
        // (matchedRule, not the default fallback — so default routing never hijacks a window).
        let belongs: (URL) -> Bool = { engine.matchedRule(for: $0)?.profileDirectory == profileDirectory }
        do {
            try controller.open(url: url, profileDirectory: profileDirectory,
                                profiles: profiles, belongsToTargetProfile: belongs)
        } catch {
            RoutingLog.logger.error("placement failed, NSWorkspace fallback: \(String(describing: error), privacy: .public)")
            openInDiaDirectly(url)
        }
    }

    private func openInDiaDirectly(_ url: URL) {
        guard let dia = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "company.thebrowser.dia") else {
            NSWorkspace.shared.open(url); return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: dia, configuration: cfg)
    }
}
```

- [ ] **Step 5: Run tests to verify pass**

Run: `swift test --filter RouterTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Full test sweep (no regressions)**

Run: `swift test`
Expected: PASS (all targets). If the executable target fails to build because `AppDelegate` still calls the old `Router()`/sync `route`, that is fixed in Task 5 — but `swift test` only builds library + test targets, so it should pass here.

- [ ] **Step 7: Commit**

```bash
git add Sources/DiaRouterShell/ProfileChooser.swift Sources/DiaRouterShell/Router.swift Tests/DiaRouterShellTests/RouterTests.swift
git commit -m "feat(shell): async Router with injected ProfileChooser and rule learning"
```

---

### Task 5: Chooser window UI + wire into the app (App)

**Files:**
- Create: `Sources/DiaProfileRouterApp/ChooserView.swift`
- Create: `Sources/DiaProfileRouterApp/ChooserWindowController.swift`
- Modify: `Sources/DiaProfileRouterApp/AppDelegate.swift`

**Interfaces:**
- Consumes: `ProfileChooser`, `ChooserResult` (Task 4), `Profile`, `RuleSuggestion.hostPattern` (Task 2), `Router` (Task 4).
- Produces: `ChooserWindowController: NSObject, ProfileChooser` (FIFO-serialized, production chooser).

> No unit tests (AppKit UI). Verified by build + manual run (Step 4).

- [ ] **Step 1: Create the SwiftUI chooser view**

```swift
// Sources/DiaProfileRouterApp/ChooserView.swift
import SwiftUI
import DiaRouterCore
import DiaRouterShell

struct ChooserView: View {
    let url: URL
    let profiles: [Profile]
    let defaultDirectory: String
    /// Called exactly once: a ChooserResult on choose, nil on cancel.
    let onDecision: (ChooserResult?) -> Void

    @State private var remember = false
    @State private var pattern: String

    init(url: URL, profiles: [Profile], defaultDirectory: String,
         onDecision: @escaping (ChooserResult?) -> Void) {
        self.url = url
        self.profiles = profiles
        self.defaultDirectory = defaultDirectory
        self.onDecision = onDecision
        _pattern = State(initialValue: RuleSuggestion.hostPattern(for: url) ?? (url.host ?? ""))
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Link öffnen in welchem Profil?").font(.headline)
            Text(url.absoluteString)
                .font(.callout).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(profiles) { profile in
                    Button { choose(profile.directory) } label: {
                        Text(profile.name).frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .modifier(DefaultActionIf(isDefault: profile.directory == defaultDirectory))
                }
            }

            Toggle("Immer diesen Host als Regel merken", isOn: $remember)
            if remember {
                TextField("Host", text: $pattern).textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Abbrechen") { onDecision(nil) }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func choose(_ directory: String) {
        let pat = (remember && !pattern.trimmingCharacters(in: .whitespaces).isEmpty)
            ? pattern.trimmingCharacters(in: .whitespaces) : nil
        onDecision(ChooserResult(profileDirectory: directory, rememberPattern: pat))
    }
}

/// Makes the default-profile button respond to Return.
private struct DefaultActionIf: ViewModifier {
    let isDefault: Bool
    func body(content: Content) -> some View {
        if isDefault { content.keyboardShortcut(.defaultAction) } else { content }
    }
}
```

- [ ] **Step 2: Create the window controller (production ProfileChooser, FIFO-serialized)**

```swift
// Sources/DiaProfileRouterApp/ChooserWindowController.swift
import AppKit
import SwiftUI
import DiaRouterCore
import DiaRouterShell

/// Shows the profile chooser in a small centered window. Serializes concurrent requests
/// (FIFO) so multiple links never stack overlapping windows.
@MainActor
final class ChooserWindowController: NSObject, ProfileChooser {
    private var tail: Task<ChooserResult?, Never>?

    func choose(url: URL, profiles: [Profile], defaultDirectory: String) async -> ChooserResult? {
        let previous = tail
        let task = Task { @MainActor [weak self] () -> ChooserResult? in
            _ = await previous?.value                       // wait our turn (FIFO)
            guard let self else { return nil }
            return await self.present(url: url, profiles: profiles, defaultDirectory: defaultDirectory)
        }
        tail = task
        return await task.value
    }

    private func present(url: URL, profiles: [Profile], defaultDirectory: String) async -> ChooserResult? {
        await withCheckedContinuation { (cont: CheckedContinuation<ChooserResult?, Never>) in
            var didResume = false
            var window: NSWindow?

            let finish: (ChooserResult?) -> Void = { result in
                guard !didResume else { return }
                didResume = true
                window?.close()
                cont.resume(returning: result)
            }

            let view = ChooserView(url: url, profiles: profiles, defaultDirectory: defaultDirectory,
                                   onDecision: finish)
            let win = NSWindow(contentViewController: NSHostingController(rootView: view))
            win.title = "Dia Profile Router"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win

            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
        }
    }
}
```

> Note: closing the window via the red button does not call `finish`; that is acceptable — the
> common dismiss paths are a profile button (result) or Esc/Abbrechen (nil). If a later iteration
> needs the title-bar close to count as cancel, add an `NSWindowDelegate.windowWillClose` that calls
> `finish(nil)`. Left out now per YAGNI.

- [ ] **Step 3: Wire the chooser into the app**

Replace `Sources/DiaProfileRouterApp/AppDelegate.swift` with:

```swift
// Sources/DiaProfileRouterApp/AppDelegate.swift
import AppKit
import DiaRouterShell

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let chooser = ChooserWindowController()
    private lazy var router = Router(chooser: chooser)

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI's MenuBarExtra lifecycle does NOT deliver http(s) URLs to
        // `application(_:open:)`, so we register the classic GetURL Apple Event handler.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(event:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleGetURL(event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: s) else { return }
        Task { @MainActor in await router.route(url) }
    }
}
```

- [ ] **Step 4: Build and manually verify**

Run: `swift build`
Expected: builds cleanly (all targets).

Manual smoke test:
```bash
./scripts/make-app.sh
cp -R "build/Dia Profile Router.app" /Applications/
# restart the running helper so the new binary is active:
osascript -e 'tell application "Dia Profile Router" to quit' 2>/dev/null; sleep 1
open "/Applications/Dia Profile Router.app"; sleep 2
# (a) rule match → no dialog, lands in correct profile:
open "https://www.porsche.com/test-rule"
# (b) no rule → chooser appears; pick a profile, optionally tick "remember":
open "https://www.example-unknown.test/test-chooser"
# verify decision logging:
log show --last 2m --predicate 'subsystem == "com.tora89.dia-profile-router"' --info --style compact
```
Expected: (a) opens without a dialog; (b) shows the chooser window centered & focused; after choosing, the link opens in that profile and (if "remember" ticked) a new host rule appears in `~/.config/dia-router/config.json`. The `log show` output shows `route … [rule]`, `needsChoice`, `chooser -> …`, and `place … -> …` lines.

- [ ] **Step 5: Commit**

```bash
git add Sources/DiaProfileRouterApp/ChooserView.swift Sources/DiaProfileRouterApp/ChooserWindowController.swift Sources/DiaProfileRouterApp/AppDelegate.swift
git commit -m "feat(app): profile chooser window wired into routing"
```

---

### Task 6: Update README

**Files:**
- Modify: `README.md` (the "How it works" reuse list and "Limitations")

**Interfaces:** none (docs only).

- [ ] **Step 1: Update "How it works"**

Replace the reuse bullet list (README.md:26-29) so it reflects: rule match → route silently; no rule → chooser (optionally learn a host rule); placement order = cache → active-tab → new profile window. Concretely set those lines to:

```text
  → rule match  →  target profile  (route silently)
  → no rule     →  ask which profile (chooser); optionally remember it as a host rule
  → the link lands in the profile via the first of:
        1. a window the app itself opened for that profile (cache) → reuse
        2. an open window whose ACTIVE tab routes (by your rules) to that profile → reuse
        3. otherwise: a new profile window via  File → New Window → "New <Profile> Window"
  → safety net (Dia unreachable): the link is handed to Dia via NSWorkspace, never lost
```

- [ ] **Step 2: Update "Limitations"**

Replace the first limitation bullet (README.md:85-86, the "If an already-open profile window shows no rule-matching page…" note) with:

```text
- Window reuse relies on a window's ACTIVE tab matching one of your rules. If a profile's window
  is currently showing an off-rule page, the router opens a fresh profile window rather than
  guessing from background tabs (which previously caused links to land in the wrong profile).
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: README reflects chooser + reliable window reuse"
```

---

## Self-Review

**Spec coverage:**
- Trigger (no rule → chooser): Task 1 (`decide`) + Task 4 (Router switch). ✓
- Chooser window UI: Task 5. ✓
- Remembered rule = host minus www, editable, no eTLD+1: Task 2 (`hostPattern`) + Task 5 (editable field) + Task 4 (write). ✓
- Cancel → default profile: Task 4 (`cancelledChooserRoutesToDefault…`). ✓
- "Remember" default OFF: Task 5 (`@State private var remember = false`). ✓
- Placement cache→active-tab→new window, drop any-tab: Task 3. ✓
- FIFO serialization of choosers: Task 5 (`tail` task chain). ✓
- Decision logging + subsystem string: Task 3 (logger) + Task 4 (Router lines). ✓
- Lost-update avoidance (fresh read before write): Task 4 (`rememberRule` calls `loadConfig()`). ✓
- Link-never-lost error handling: Task 4 (`place` catch → `openInDiaDirectly`; rule save error logged not fatal). ✓
- Threading (async route, Task in handleGetURL): Task 4 + Task 5. ✓
- README update: Task 6. ✓

**Placeholder scan:** No TBD/TODO; all code blocks complete; the only "later iteration" note (title-bar close = cancel) is an explicit YAGNI deferral, not a gap. ✓

**Type consistency:** `RouteDecision` cases, `ChooserResult(profileDirectory:rememberPattern:)`, `ProfileChooser.choose(url:profiles:defaultDirectory:)`, `Router.init(runner:chooser:configPath:localStatePath:)`, `RuleSuggestion.hostPattern(for:)` / `.appended(_:to:)` are used identically across tasks. `FakeRunner` reused from existing DiaControllerTests within the same test target. ✓
