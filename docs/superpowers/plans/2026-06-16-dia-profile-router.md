# Dia Profile Router Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eine macOS-Menubar-App, die als Standardbrowser jeden Link gegen konfigurierbare Regeln prüft und ihn im passenden Dia-Profil öffnet (Default-Profil als Fallback), mit GUI zur Regelpflege.

**Architecture:** SwiftPM-Paket mit (a) reinem, unit-getestetem Logik-Kern `DiaRouterCore` (Modelle, Wildcard, RuleEngine, ProfileStore, ProfileWindowMap, ConfigStore) und (b) App-Shell `DiaProfileRouterApp` (SwiftUI `MenuBarExtra`, AppleScript-`DiaController`, Default-Browser-Bridge via `NSWorkspace`, App-Bundle). URL-Routing in ein Profil erfolgt via AppleScript `make new tab at window id <UUID>`, wobei die Fenster-UUID über `StorableProfileContainers.json` einem Profil zugeordnet wird; fehlt ein Profilfenster, erzeugt UI-Automation es über den Menüeintrag „New Window – ‹Profil›".

**Tech Stack:** Swift 6.3, SwiftPM, Swift Testing (`import Testing`), SwiftUI (`MenuBarExtra`, macOS 13+), AppleScript via `NSAppleScript`, `NSWorkspace.setDefaultApplication`.

**Design-Referenz:** `docs/plans/2026-06-16-dia-profile-router-design.md`

---

## File Structure

```
dia-profile-router/
  Package.swift
  Sources/
    DiaRouterCore/
      Models.swift          # Profile, MatchType, Rule, RouterConfig
      URLNormalize.swift     # einheitliche URL→String-Normalisierung
      Wildcard.swift         # *-Wildcard-Matching (aus Finicky portiert)
      RuleEngine.swift       # URL -> ProfileDirectory (Regel-Treffer oder Default)
      ProfileStore.swift     # Dia Local State -> [Profile]
      ProfileWindowMap.swift # StorableProfileContainers.json -> [windowUUID: profileDir]
      ConfigStore.swift      # Laden/Speichern RouterConfig (JSON)
    DiaProfileRouterApp/
      DiaApp.swift           # @main App + MenuBarExtra + AppDelegate-Adaptor
      AppDelegate.swift      # application(_:open:) -> Routing
      AppleScriptRunning.swift # Protokoll + NSAppleScript-Impl (injizierbar)
      DiaController.swift    # Routing-Entscheidung + AppleScript/Menü-Fallback
      DefaultBrowser.swift   # NSWorkspace default-handler set/query
      Router.swift           # bindet RuleEngine+DiaController, Einstiegspunkt fürs Routing
      SettingsView.swift     # SwiftUI Konfig-GUI
  Tests/
    DiaRouterCoreTests/
      ModelsTests.swift
      WildcardTests.swift
      RuleEngineTests.swift
      ProfileStoreTests.swift
      ProfileWindowMapTests.swift
      ConfigStoreTests.swift
      Fixtures/
        LocalState.json
        StorableProfileContainers.json
    DiaProfileRouterAppTests/
      DiaControllerTests.swift
  Resources/
    Info.plist               # LSUIElement + CFBundleURLTypes http/https
  scripts/
    make-app.sh              # baut .app-Bundle + registriert es
```

**Verantwortungs-Grenzen:** `DiaRouterCore` ist plattform-logisch rein (keine AppKit/AppleScript-Abhängigkeit) → vollständig per `swift test` testbar. Die App-Shell kapselt alle Seiteneffekte; `DiaController` wird über ein `AppleScriptRunning`-Protokoll testbar gemacht (Entscheidungslogik unit-getestet, echte AppleScript-Ausführung nur manuell).

---

## Task 0: Projekt-Scaffold (SwiftPM)

**Files:**
- Create: `Package.swift`

- [ ] **Step 1: Package.swift schreiben**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiaProfileRouter",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "DiaRouterCore"),
        .testTarget(
            name: "DiaRouterCoreTests",
            dependencies: ["DiaRouterCore"],
            resources: [.copy("Fixtures")]
        ),
        .executableTarget(
            name: "DiaProfileRouterApp",
            dependencies: ["DiaRouterCore"]
        ),
        .testTarget(
            name: "DiaProfileRouterAppTests",
            dependencies: ["DiaProfileRouterApp"]
        ),
    ]
)
```

- [ ] **Step 2: Leere Quell-Ordner + Platzhalter anlegen (damit SwiftPM die Targets findet)**

```bash
mkdir -p Sources/DiaRouterCore Sources/DiaProfileRouterApp \
         Tests/DiaRouterCoreTests/Fixtures Tests/DiaProfileRouterAppTests Resources scripts
echo "// DiaRouterCore" > Sources/DiaRouterCore/Placeholder.swift
printf 'import AppKit\nimport SwiftUI\n\n// entry point added in later task\n' > Sources/DiaProfileRouterApp/main.swift
```

- [ ] **Step 3: Build prüfen**

Run: `swift build`
Expected: erfolgreicher Build (nur Platzhalter).

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources Tests Resources scripts
git commit -m "chore: scaffold SwiftPM package for Dia Profile Router"
```

---

## Task 1: Datenmodelle

**Files:**
- Create: `Sources/DiaRouterCore/Models.swift`
- Test: `Tests/DiaRouterCoreTests/ModelsTests.swift`
- Delete later: `Sources/DiaRouterCore/Placeholder.swift`

- [ ] **Step 1: Failing test schreiben**

```swift
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
```

- [ ] **Step 2: Test laufen lassen (muss fehlschlagen)**

Run: `swift test --filter ModelsTests`
Expected: FAIL — Typen `RouterConfig`/`Rule`/`Profile` unbekannt.

- [ ] **Step 3: Modelle implementieren**

```swift
// Sources/DiaRouterCore/Models.swift
import Foundation

public struct Profile: Equatable, Codable, Identifiable, Sendable {
    public let directory: String   // z.B. "Profile 6" oder "Default"
    public let name: String        // Anzeigename, z.B. "Work"
    public var id: String { directory }
    public init(directory: String, name: String) {
        self.directory = directory
        self.name = name
    }
}

public enum MatchType: String, Codable, CaseIterable, Sendable {
    case exact    // voller URL-String (normalisiert)
    case prefix   // host+path beginnt mit Pattern
    case host     // host == Pattern oder Subdomain davon
    case wildcard // * als Platzhalter; ohne "/" gegen host, sonst gegen host+path
}

public struct Rule: Equatable, Codable, Identifiable, Sendable {
    public let id: UUID
    public var matchType: MatchType
    public var pattern: String
    public var profileDirectory: String
    public init(id: UUID = UUID(), matchType: MatchType, pattern: String, profileDirectory: String) {
        self.id = id
        self.matchType = matchType
        self.pattern = pattern
        self.profileDirectory = profileDirectory
    }
}

public struct RouterConfig: Equatable, Codable, Sendable {
    public var rules: [Rule]
    public var defaultProfileDirectory: String
    public init(rules: [Rule], defaultProfileDirectory: String) {
        self.rules = rules
        self.defaultProfileDirectory = defaultProfileDirectory
    }
}
```

- [ ] **Step 4: Platzhalter entfernen, Test laufen lassen (muss bestehen)**

```bash
rm Sources/DiaRouterCore/Placeholder.swift
```
Run: `swift test --filter ModelsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/DiaRouterCore/Models.swift Tests/DiaRouterCoreTests/ModelsTests.swift
git rm Sources/DiaRouterCore/Placeholder.swift
git commit -m "feat(core): add Profile, Rule, RouterConfig models"
```

---

## Task 2: URL-Normalisierung

**Files:**
- Create: `Sources/DiaRouterCore/URLNormalize.swift`
- Test: `Tests/DiaRouterCoreTests/RuleEngineTests.swift` (gemeinsam mit Task 3 angelegt; hier nur Normalize-Tests vorab)

- [ ] **Step 1: Failing test schreiben**

```swift
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
```

- [ ] **Step 2: Test laufen lassen (muss fehlschlagen)**

Run: `swift test --filter RuleEngineTests/normalize`
Expected: FAIL — `URLNormalize` unbekannt.

- [ ] **Step 3: Implementieren**

```swift
// Sources/DiaRouterCore/URLNormalize.swift
import Foundation

public enum URLNormalize {
    /// Kleingeschriebener Host, ohne Trailing-Slash am Pfad.
    public static func host(_ url: URL) -> String {
        (url.host ?? "").lowercased()
    }

    /// "host/path" kleingeschrieben, ohne Fragment/Query, ohne Trailing-Slash.
    public static func hostPath(_ url: URL) -> String {
        let h = host(url)
        var p = url.path
        if p.hasSuffix("/") { p.removeLast() }
        return (h + p)
    }

    /// Vollständiger normalisierter String für exakte Vergleiche (scheme+host+path, ohne Fragment).
    public static func full(_ url: URL) -> String {
        let scheme = (url.scheme ?? "https").lowercased()
        return "\(scheme)://\(hostPath(url))"
    }
}
```

- [ ] **Step 4: Test laufen lassen (muss bestehen)**

Run: `swift test --filter RuleEngineTests/normalize`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/DiaRouterCore/URLNormalize.swift Tests/DiaRouterCoreTests/RuleEngineTests.swift
git commit -m "feat(core): add URL normalization helpers"
```

---

## Task 3: Wildcard-Matching (aus Finicky portiert)

**Files:**
- Create: `Sources/DiaRouterCore/Wildcard.swift`
- Test: `Tests/DiaRouterCoreTests/WildcardTests.swift`

**Hinweis:** Logik portiert aus Finicky `packages/config-api/src/wildcard.ts` (MIT). `*` = beliebige Zeichenfolge (auch leer); restliche Zeichen literal; voller String-Match.

- [ ] **Step 1: Failing tests schreiben**

```swift
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
    #expect(Wildcard.matches(pattern: "*/sites/Docs*", value: "team.example.org/sites/Docs/Docs"))
}

@Test func literalSpecialCharsAreEscaped() {
    #expect(Wildcard.matches(pattern: "a.b", value: "a.b"))
    #expect(!Wildcard.matches(pattern: "a.b", value: "axb"))
}

@Test func emptyStarMatchesEmpty() {
    #expect(Wildcard.matches(pattern: "*", value: ""))
    #expect(Wildcard.matches(pattern: "*", value: "anything/here"))
}
```

- [ ] **Step 2: Test laufen lassen (muss fehlschlagen)**

Run: `swift test --filter WildcardTests`
Expected: FAIL — `Wildcard` unbekannt.

- [ ] **Step 3: Implementieren**

```swift
// Sources/DiaRouterCore/Wildcard.swift
// Portiert aus Finicky (johnste/finicky), packages/config-api/src/wildcard.ts — MIT License.
import Foundation

public enum Wildcard {
    /// Voller Match: `*` steht für beliebige (auch leere) Zeichenfolge; alles andere literal.
    public static func matches(pattern: String, value: String) -> Bool {
        let regex = "^" + pattern
            .components(separatedBy: "*")
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: ".*") + "$"
        guard let re = try? NSRegularExpression(pattern: regex, options: [.dotMatchesLineSeparators]) else {
            return false
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return re.firstMatch(in: value, options: [], range: range) != nil
    }
}
```

- [ ] **Step 4: Test laufen lassen (muss bestehen)**

Run: `swift test --filter WildcardTests`
Expected: PASS (alle 5).

- [ ] **Step 5: Commit**

```bash
git add Sources/DiaRouterCore/Wildcard.swift Tests/DiaRouterCoreTests/WildcardTests.swift
git commit -m "feat(core): add wildcard matching ported from Finicky (MIT)"
```

---

## Task 4: RuleEngine

**Files:**
- Create: `Sources/DiaRouterCore/RuleEngine.swift`
- Test: `Tests/DiaRouterCoreTests/RuleEngineTests.swift` (Teil 2 ergänzen)

- [ ] **Step 1: Failing tests ergänzen**

```swift
// Tests/DiaRouterCoreTests/RuleEngineTests.swift  (Teil 2: anhängen)

private func engine(_ rules: [Rule], default def: String = "Profile 6") -> RuleEngine {
    RuleEngine(config: RouterConfig(rules: rules, defaultProfileDirectory: def))
}

@Test func hostRuleMatchesSubdomains() {
    let e = engine([Rule(matchType: .host, pattern: "example.com", profileDirectory: "Profile 10")])
    #expect(e.profileDirectory(for: URL(string: "https://app.example.com/jira")!) == "Profile 10")
    #expect(e.profileDirectory(for: URL(string: "https://example.com")!) == "Profile 10")
}

@Test func prefixRuleMatchesHostPathPrefix() {
    let e = engine([Rule(matchType: .prefix, pattern: "team.example.org/sites/Docs", profileDirectory: "Profile 6")])
    #expect(e.profileDirectory(for: URL(string: "https://team.example.org/sites/Docs/Docs")!) == "Profile 6")
    #expect(e.profileDirectory(for: URL(string: "https://team.example.org/sites/Other")!) == "Profile 6"/*default*/)
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
    #expect(e.profileDirectory(for: URL(string: "https://team.example.org/sites/Docs/Docs")!) == "Profile 6")
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
```

- [ ] **Step 2: Test laufen lassen (muss fehlschlagen)**

Run: `swift test --filter RuleEngineTests`
Expected: FAIL — `RuleEngine`/`profileDirectory(for:)` unbekannt.

- [ ] **Step 3: Implementieren**

```swift
// Sources/DiaRouterCore/RuleEngine.swift
import Foundation

public struct RuleEngine: Sendable {
    public let config: RouterConfig
    public init(config: RouterConfig) { self.config = config }

    /// Liefert die Ziel-Profilverzeichnis-ID; bei keinem Treffer das Default-Profil.
    public func profileDirectory(for url: URL) -> String {
        matchedRule(for: url)?.profileDirectory ?? config.defaultProfileDirectory
    }

    public func matchedRule(for url: URL) -> Rule? {
        config.rules.first { matches($0, url) }
    }

    private func matches(_ rule: Rule, _ url: URL) -> Bool {
        let host = URLNormalize.host(url)
        let hostPath = URLNormalize.hostPath(url)
        switch rule.matchType {
        case .exact:
            return URLNormalize.full(url) == rule.pattern.lowercased()
                || hostPath == rule.pattern.lowercased()
        case .prefix:
            return hostPath.hasPrefix(rule.pattern.lowercased())
        case .host:
            let p = rule.pattern.lowercased()
            return host == p || host.hasSuffix("." + p)
        case .wildcard:
            let target = rule.pattern.contains("/") ? hostPath : host
            return Wildcard.matches(pattern: rule.pattern.lowercased(), value: target)
        }
    }
}
```

> Hinweis: `exact` akzeptiert sowohl voll-normalisierte URL (`https://host/path`) als auch reines `host/path`, damit Nutzer das Schema weglassen können.

- [ ] **Step 4: Test laufen lassen (muss bestehen)**

Run: `swift test --filter RuleEngineTests`
Expected: PASS (alle Teile inkl. Normalisierung aus Task 2).

- [ ] **Step 5: Commit**

```bash
git add Sources/DiaRouterCore/RuleEngine.swift Tests/DiaRouterCoreTests/RuleEngineTests.swift
git commit -m "feat(core): add RuleEngine with exact/prefix/host/wildcard matching"
```

---

## Task 5: ProfileStore (Dia Local State lesen)

**Files:**
- Create: `Sources/DiaRouterCore/ProfileStore.swift`
- Create: `Tests/DiaRouterCoreTests/Fixtures/LocalState.json`
- Test: `Tests/DiaRouterCoreTests/ProfileStoreTests.swift`

- [ ] **Step 1: Fixture anlegen** (verkürztes echtes Format)

```json
// Tests/DiaRouterCoreTests/Fixtures/LocalState.json
{
  "profile": {
    "info_cache": {
      "Profile 6": { "name": "Work" },
      "Profile 10": { "name": "Client A" },
      "Profile 4": { "name": "Personal" }
    },
    "last_used": "Profile 6"
  }
}
```

- [ ] **Step 2: Failing test schreiben**

```swift
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
```

- [ ] **Step 3: Test laufen lassen (muss fehlschlagen)**

Run: `swift test --filter ProfileStoreTests`
Expected: FAIL — `ProfileStore` unbekannt.

- [ ] **Step 4: Implementieren**

```swift
// Sources/DiaRouterCore/ProfileStore.swift
import Foundation

public enum ProfileStore {
    /// Standardpfad zu Dias Local State.
    public static func defaultLocalStatePath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dia/User Data/Local State")
    }

    private struct LocalState: Decodable {
        struct ProfileSection: Decodable {
            struct Info: Decodable { let name: String? }
            let info_cache: [String: Info]
        }
        let profile: ProfileSection
    }

    public static func loadProfiles(localStatePath: URL) throws -> [Profile] {
        let data = try Data(contentsOf: localStatePath)
        let state = try JSONDecoder().decode(LocalState.self, from: data)
        return state.profile.info_cache
            .map { Profile(directory: $0.key, name: $0.value.name ?? $0.key) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
```

- [ ] **Step 5: Test laufen lassen (muss bestehen)**

Run: `swift test --filter ProfileStoreTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/DiaRouterCore/ProfileStore.swift Tests/DiaRouterCoreTests/ProfileStoreTests.swift Tests/DiaRouterCoreTests/Fixtures/LocalState.json
git commit -m "feat(core): add ProfileStore reading Dia Local State"
```

---

## Task 6: ProfileWindowMap (Fenster-UUID → Profil)

**Files:**
- Create: `Sources/DiaRouterCore/ProfileWindowMap.swift`
- Create: `Tests/DiaRouterCoreTests/Fixtures/StorableProfileContainers.json`
- Test: `Tests/DiaRouterCoreTests/ProfileWindowMapTests.swift`

- [ ] **Step 1: Fixture anlegen** (echte Struktur, gekürzt)

```json
// Tests/DiaRouterCoreTests/Fixtures/StorableProfileContainers.json
{
  "version": 3,
  "containers": [
    { "id": { "container": { "favorites": {} }, "profileID": "Profile 6" }, "tabs": [] },
    { "id": { "container": { "window": { "_0": "62D872AB-DDA4-46E1-81B3-1D7F7DAC5387" } }, "profileID": "Profile 6" }, "tabs": [] },
    { "id": { "container": { "window": { "_0": "8C3C2822-ADC4-4EF7-ABBF-9ECF4576D809" } }, "profileID": "Profile 10" }, "tabs": [] }
  ]
}
```

- [ ] **Step 2: Failing test schreiben**

```swift
// Tests/DiaRouterCoreTests/ProfileWindowMapTests.swift
import Testing
import Foundation
@testable import DiaRouterCore

private func fixture(_ name: String) -> URL {
    Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")!
}

@Test func mapsWindowUUIDToProfileDirectory() throws {
    let map = try ProfileWindowMap.load(containersPath: fixture("StorableProfileContainers"))
    #expect(map["62D872AB-DDA4-46E1-81B3-1D7F7DAC5387"] == "Profile 6")
    #expect(map["8C3C2822-ADC4-4EF7-ABBF-9ECF4576D809"] == "Profile 10")
    // Container ohne window-UUID liefert keinen Eintrag
    #expect(map.count == 2)
}

@Test func windowsForProfileReturnsAllMatchingUUIDs() throws {
    let map = try ProfileWindowMap.load(containersPath: fixture("StorableProfileContainers"))
    #expect(ProfileWindowMap.windows(forProfile: "Profile 6", in: map) == ["62D872AB-DDA4-46E1-81B3-1D7F7DAC5387"])
}
```

- [ ] **Step 3: Test laufen lassen (muss fehlschlagen)**

Run: `swift test --filter ProfileWindowMapTests`
Expected: FAIL — `ProfileWindowMap` unbekannt.

- [ ] **Step 4: Implementieren**

```swift
// Sources/DiaRouterCore/ProfileWindowMap.swift
import Foundation

public enum ProfileWindowMap {
    public static func defaultContainersPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dia/StorableProfileContainers.json")
    }

    /// windowUUID -> profileDirectory ("Profile N" / "Default").
    public static func load(containersPath: URL) throws -> [String: String] {
        let data = try Data(contentsOf: containersPath)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let containers = root?["containers"] as? [[String: Any]] ?? []
        var map: [String: String] = [:]
        for c in containers {
            guard let id = c["id"] as? [String: Any],
                  let profileID = id["profileID"] as? String,
                  let container = id["container"] as? [String: Any],
                  let window = container["window"] as? [String: Any],
                  let uuid = window["_0"] as? String else { continue }
            map[uuid] = profileID
        }
        return map
    }

    public static func windows(forProfile dir: String, in map: [String: String]) -> [String] {
        map.filter { $0.value == dir }.map(\.key).sorted()
    }
}
```

- [ ] **Step 5: Test laufen lassen (muss bestehen)**

Run: `swift test --filter ProfileWindowMapTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/DiaRouterCore/ProfileWindowMap.swift Tests/DiaRouterCoreTests/ProfileWindowMapTests.swift Tests/DiaRouterCoreTests/Fixtures/StorableProfileContainers.json
git commit -m "feat(core): add ProfileWindowMap (window UUID -> profile)"
```

---

## Task 7: ConfigStore

**Files:**
- Create: `Sources/DiaRouterCore/ConfigStore.swift`
- Test: `Tests/DiaRouterCoreTests/ConfigStoreTests.swift`

- [ ] **Step 1: Failing test schreiben**

```swift
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
```

- [ ] **Step 2: Test laufen lassen (muss fehlschlagen)**

Run: `swift test --filter ConfigStoreTests`
Expected: FAIL — `ConfigStore` unbekannt.

- [ ] **Step 3: Implementieren**

```swift
// Sources/DiaRouterCore/ConfigStore.swift
import Foundation

public enum ConfigStore {
    public static func defaultPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/dia-router/config.json")
    }

    public static func save(_ config: RouterConfig, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> RouterConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RouterConfig.self, from: data)
    }

    public static func loadOrDefault(from url: URL, defaultProfileDirectory: String) throws -> RouterConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return RouterConfig(rules: [], defaultProfileDirectory: defaultProfileDirectory)
        }
        return try load(from: url)
    }
}
```

- [ ] **Step 4: Test laufen lassen (muss bestehen)**

Run: `swift test --filter ConfigStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/DiaRouterCore/ConfigStore.swift Tests/DiaRouterCoreTests/ConfigStoreTests.swift
git commit -m "feat(core): add ConfigStore (JSON persistence)"
```

---

## Task 8: AppleScript-Abstraktion (injizierbar)

**Files:**
- Create: `Sources/DiaProfileRouterApp/AppleScriptRunning.swift`

- [ ] **Step 1: Protokoll + echte Implementierung schreiben** (kein eigener Test — wird in Task 9 über Fake getestet)

```swift
// Sources/DiaProfileRouterApp/AppleScriptRunning.swift
import Foundation
import AppKit

public protocol AppleScriptRunning {
    /// Führt ein AppleScript aus und liefert das String-Ergebnis (oder wirft bei Fehler).
    @discardableResult
    func run(_ source: String) throws -> String
}

public struct AppleScriptError: Error { public let message: String }

public struct NSAppleScriptRunner: AppleScriptRunning {
    public init() {}
    @discardableResult
    public func run(_ source: String) throws -> String {
        var errorDict: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw AppleScriptError(message: "Konnte AppleScript nicht erstellen")
        }
        let result = script.executeAndReturnError(&errorDict)
        if let error = errorDict {
            throw AppleScriptError(message: "\(error[NSAppleScript.errorMessage] ?? "unbekannt")")
        }
        return result.stringValue ?? ""
    }
}
```

- [ ] **Step 2: Build prüfen**

Run: `swift build`
Expected: erfolgreicher Build.

- [ ] **Step 3: Commit**

```bash
git add Sources/DiaProfileRouterApp/AppleScriptRunning.swift
git commit -m "feat(app): add injectable AppleScript runner abstraction"
```

---

## Task 9: DiaController (Routing-Entscheidung)

**Files:**
- Create: `Sources/DiaProfileRouterApp/DiaController.swift`
- Test: `Tests/DiaProfileRouterAppTests/DiaControllerTests.swift`

Der Controller bekommt: (a) die Profil→Fenster-Map, (b) die Liste **aktuell offener** Fenster-UUIDs (per AppleScript), (c) den AppleScript-Runner. Er entscheidet: existierendes Fenster → Tab dort; sonst Menü-Fallback. Getestet wird die **Entscheidung** (welcher AppleScript-Quelltext wird erzeugt) über einen Fake-Runner.

- [ ] **Step 1: Failing tests schreiben**

```swift
// Tests/DiaProfileRouterAppTests/DiaControllerTests.swift
import Testing
import Foundation
@testable import DiaProfileRouterApp
import DiaRouterCore

final class FakeRunner: AppleScriptRunning, @unchecked Sendable {
    var scripts: [String] = []
    /// Antwort, die `run` für das Fenster-Listing zurückgibt.
    var windowListResponse = ""
    func run(_ source: String) throws -> String {
        scripts.append(source)
        if source.contains("id of every window") { return windowListResponse }
        return ""
    }
}

@Test func opensTabInExistingProfileWindow() throws {
    let runner = FakeRunner()
    // Live offen: ein Fenster mit UUID, das laut Map zu Profile 10 gehört
    runner.windowListResponse = "8C3C2822-ADC4-4EF7-ABBF-9ECF4576D809"
    let controller = DiaController(
        runner: runner,
        windowMap: ["8C3C2822-ADC4-4EF7-ABBF-9ECF4576D809": "Profile 10"],
        profiles: [Profile(directory: "Profile 10", name: "Client A")]
    )
    try controller.open(url: URL(string: "https://example.com")!, profileDirectory: "Profile 10")

    // Es muss ein "make new tab at window id <UUID>"-Script erzeugt worden sein
    #expect(runner.scripts.contains { $0.contains("make new tab") && $0.contains("8C3C2822-ADC4-4EF7-ABBF-9ECF4576D809") })
    // KEIN Menü-Fallback
    #expect(!runner.scripts.contains { $0.contains("System Events") })
}

@Test func fallsBackToMenuWhenNoProfileWindowOpen() throws {
    let runner = FakeRunner()
    runner.windowListResponse = ""  // kein Fenster offen
    let controller = DiaController(
        runner: runner,
        windowMap: [:],
        profiles: [Profile(directory: "Profile 7", name: "Community")]
    )
    try controller.open(url: URL(string: "https://example.com")!, profileDirectory: "Profile 7")

    // Menü-Fallback nutzt den Profilnamen "Community"
    #expect(runner.scripts.contains { $0.contains("System Events") && $0.contains("Community") })
}
```

- [ ] **Step 2: Test laufen lassen (muss fehlschlagen)**

Run: `swift test --filter DiaControllerTests`
Expected: FAIL — `DiaController` unbekannt.

- [ ] **Step 3: Implementieren**

```swift
// Sources/DiaProfileRouterApp/DiaController.swift
import Foundation
import DiaRouterCore

public struct DiaController {
    let runner: AppleScriptRunning
    let windowMap: [String: String]   // windowUUID -> profileDir
    let profiles: [Profile]

    public init(runner: AppleScriptRunning, windowMap: [String: String], profiles: [Profile]) {
        self.runner = runner
        self.windowMap = windowMap
        self.profiles = profiles
    }

    public func open(url: URL, profileDirectory: String) throws {
        let liveWindows = try liveWindowUUIDs()
        // Fenster, die laut Map zum Zielprofil gehören UND aktuell offen sind
        let candidate = liveWindows.first { windowMap[$0] == profileDirectory }

        if let windowUUID = candidate {
            try openTab(url: url, inWindow: windowUUID)
            return
        }
        // Fallback: Profilfenster per Menü erzeugen, dann Tab dort
        if let name = profiles.first(where: { $0.directory == profileDirectory })?.name {
            try openNewWindowViaMenu(profileName: name)
            // Nach Fenster-Erzeugung: neues Frontfenster bekommt den Tab
            try openTabInFrontWindow(url: url)
        } else {
            // Letzte Rückfallebene: ins Frontfenster (Default-Profil)
            try openTabInFrontWindow(url: url)
        }
    }

    private func liveWindowUUIDs() throws -> [String] {
        let script = #"""
        tell application "Dia"
            set ids to id of every window
            set AppleScript's text item delimiters to "\n"
            return ids as text
        end tell
        """#
        let out = try runner.run(script)
        return out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private func openTab(url: URL, inWindow uuid: String) throws {
        let script = """
        tell application "Dia"
            make new tab at end of tabs of (first window whose id is "\(uuid)") with properties {URL:"\(escaped(url.absoluteString))"}
        end tell
        """
        try runner.run(script)
    }

    private func openTabInFrontWindow(url: URL) throws {
        let script = """
        tell application "Dia"
            make new tab at end of tabs of front window with properties {URL:"\(escaped(url.absoluteString))"}
        end tell
        """
        try runner.run(script)
    }

    private func openNewWindowViaMenu(profileName: String) throws {
        // Klickt Dias Menüeintrag "New Window – ‹Profilname›" (tolerant per Name-Enthält).
        let script = """
        tell application "Dia" to activate
        tell application "System Events"
            tell process "Dia"
                set targetItem to missing value
                repeat with mb in menu bars
                    repeat with mbi in menu bar items of mb
                        try
                            repeat with mi in menu items of menu 1 of mbi
                                if name of mi contains "\(escaped(profileName))" and name of mi contains "Window" then
                                    set targetItem to mi
                                    exit repeat
                                end if
                            end repeat
                        end try
                        if targetItem is not missing value then exit repeat
                    end repeat
                    if targetItem is not missing value then exit repeat
                end repeat
                if targetItem is not missing value then click targetItem
            end tell
        end tell
        """
        try runner.run(script)
    }

    private func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
```

> Hinweis: Die Menü-Navigation ist absichtlich tolerant (sucht über alle Menüs nach einem Eintrag, dessen Name den Profilnamen **und** „Window" enthält), damit Layout-Änderungen in Dia nicht sofort brechen.

- [ ] **Step 4: Test laufen lassen (muss bestehen)**

Run: `swift test --filter DiaControllerTests`
Expected: PASS (beide Tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DiaProfileRouterApp/DiaController.swift Tests/DiaProfileRouterAppTests/DiaControllerTests.swift
git commit -m "feat(app): add DiaController with window-routing + menu fallback"
```

---

## Task 10: DefaultBrowser-Bridge

**Files:**
- Create: `Sources/DiaProfileRouterApp/DefaultBrowser.swift`

**Hinweis:** Statt der ObjC-`LSSetDefaultHandlerForURLScheme`-Variante aus Finicky nutzen wir die moderne Swift-API `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` (macOS 12+) — gleiches Ziel, ohne ObjC-Bridge.

- [ ] **Step 1: Implementieren** (manuell verifiziert, kein Unit-Test)

```swift
// Sources/DiaProfileRouterApp/DefaultBrowser.swift
import AppKit

public enum DefaultBrowser {
    /// Ist diese App aktuell Standard-Handler für http?
    public static func isDefault() -> Bool {
        guard let url = URL(string: "https://example.com"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: url) else { return false }
        return handler == Bundle.main.bundleURL
    }

    /// Setzt diese App als Standard für http+https (öffnet Systemdialog zur Bestätigung).
    public static func setAsDefault() {
        let appURL = Bundle.main.bundleURL
        for scheme in ["http", "https"] {
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: scheme) { error in
                if let error { NSLog("setDefaultApplication(\(scheme)) failed: \(error)") }
            }
        }
    }
}
```

- [ ] **Step 2: Build prüfen**

Run: `swift build`
Expected: erfolgreicher Build.

- [ ] **Step 3: Commit**

```bash
git add Sources/DiaProfileRouterApp/DefaultBrowser.swift
git commit -m "feat(app): add default-browser registration via NSWorkspace"
```

---

## Task 11: Router (Verdrahtung Core ↔ Controller)

**Files:**
- Create: `Sources/DiaProfileRouterApp/Router.swift`

- [ ] **Step 1: Implementieren**

```swift
// Sources/DiaProfileRouterApp/Router.swift
import AppKit
import DiaRouterCore

/// Bindet Config, Profile, Fenster-Map und DiaController zusammen.
public struct Router {
    let runner: AppleScriptRunning
    public init(runner: AppleScriptRunning = NSAppleScriptRunner()) { self.runner = runner }

    public func route(_ url: URL) {
        do {
            let config = try ConfigStore.loadOrDefault(
                from: ConfigStore.defaultPath(), defaultProfileDirectory: "Default")
            let profiles = (try? ProfileStore.loadProfiles(
                localStatePath: ProfileStore.defaultLocalStatePath())) ?? []
            let windowMap = (try? ProfileWindowMap.load(
                containersPath: ProfileWindowMap.defaultContainersPath())) ?? [:]

            let engine = RuleEngine(config: config)
            let target = engine.profileDirectory(for: url)

            let controller = DiaController(runner: runner, windowMap: windowMap, profiles: profiles)
            try controller.open(url: url, profileDirectory: target)
        } catch {
            // Degradation: Link nie verlieren -> an Dia (Default-Profil) durchreichen
            NSLog("Routing fehlgeschlagen, Fallback NSWorkspace: \(error)")
            openInDiaDirectly(url)
        }
    }

    private func openInDiaDirectly(_ url: URL) {
        guard let dia = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "company.thebrowser.dia") else {
            NSWorkspace.shared.open(url); return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: dia, configuration: cfg)
    }
}
```

- [ ] **Step 2: Build prüfen**

Run: `swift build`
Expected: erfolgreicher Build.

- [ ] **Step 3: Commit**

```bash
git add Sources/DiaProfileRouterApp/Router.swift
git commit -m "feat(app): wire RuleEngine + DiaController into Router"
```

---

## Task 12: App-Einstieg + URL-Empfang + Menubar

**Files:**
- Create: `Sources/DiaProfileRouterApp/AppDelegate.swift`
- Create: `Sources/DiaProfileRouterApp/DiaApp.swift`
- Delete: `Sources/DiaProfileRouterApp/main.swift`

- [ ] **Step 1: AppDelegate (empfängt geöffnete URLs)**

```swift
// Sources/DiaProfileRouterApp/AppDelegate.swift
import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    let router = Router()
    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { router.route(url) }
    }
}
```

- [ ] **Step 2: SwiftUI-App mit MenuBarExtra**

```swift
// Sources/DiaProfileRouterApp/DiaApp.swift
import SwiftUI

@main
struct DiaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        MenuBarExtra("Dia Router", systemImage: "arrow.triangle.branch") {
            SettingsView()
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 3: alten Platzhalter entfernen**

```bash
rm Sources/DiaProfileRouterApp/main.swift
```

- [ ] **Step 4: SettingsView-Stub (damit es baut; volle UI in Task 13)**

```swift
// Sources/DiaProfileRouterApp/SettingsView.swift
import SwiftUI
struct SettingsView: View {
    var body: some View { Text("Dia Router").padding() }
}
```

- [ ] **Step 5: Build prüfen**

Run: `swift build`
Expected: erfolgreicher Build (Executable mit `@main`).

- [ ] **Step 6: Commit**

```bash
git add Sources/DiaProfileRouterApp/AppDelegate.swift Sources/DiaProfileRouterApp/DiaApp.swift Sources/DiaProfileRouterApp/SettingsView.swift
git rm Sources/DiaProfileRouterApp/main.swift
git commit -m "feat(app): add @main MenuBarExtra app + URL reception"
```

---

## Task 13: Konfig-GUI (SettingsView)

**Files:**
- Modify: `Sources/DiaProfileRouterApp/SettingsView.swift`
- Create: `Sources/DiaProfileRouterApp/ConfigViewModel.swift`

- [ ] **Step 1: ViewModel (lädt/speichert Config + Profile)**

```swift
// Sources/DiaProfileRouterApp/ConfigViewModel.swift
import SwiftUI
import DiaRouterCore

@MainActor
final class ConfigViewModel: ObservableObject {
    @Published var config: RouterConfig
    @Published var profiles: [Profile] = []
    @Published var isDefaultBrowser = false

    init() {
        let profs = (try? ProfileStore.loadProfiles(localStatePath: ProfileStore.defaultLocalStatePath())) ?? []
        self.profiles = profs
        let def = profs.first?.directory ?? "Default"
        self.config = (try? ConfigStore.loadOrDefault(from: ConfigStore.defaultPath(), defaultProfileDirectory: def))
            ?? RouterConfig(rules: [], defaultProfileDirectory: def)
        self.isDefaultBrowser = DefaultBrowser.isDefault()
    }

    func save() {
        try? ConfigStore.save(config, to: ConfigStore.defaultPath())
    }

    func addRule() {
        let def = profiles.first?.directory ?? config.defaultProfileDirectory
        config.rules.append(Rule(matchType: .host, pattern: "", profileDirectory: def))
        save()
    }

    func deleteRule(_ rule: Rule) {
        config.rules.removeAll { $0.id == rule.id }
        save()
    }

    func profileName(_ dir: String) -> String {
        profiles.first { $0.directory == dir }?.name ?? dir
    }

    func setAsDefaultBrowser() {
        DefaultBrowser.setAsDefault()
        isDefaultBrowser = DefaultBrowser.isDefault()
    }
}
```

- [ ] **Step 2: SettingsView (Regelliste, Default-Profil, Standardbrowser-Button)**

```swift
// Sources/DiaProfileRouterApp/SettingsView.swift
import SwiftUI
import DiaRouterCore

struct SettingsView: View {
    @StateObject private var vm = ConfigViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Dia Profile Router").font(.headline)
                Spacer()
                if vm.isDefaultBrowser {
                    Label("Standardbrowser", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                } else {
                    Button("Als Standardbrowser setzen") { vm.setAsDefaultBrowser() }
                }
            }

            Divider()

            HStack {
                Text("Default-Profil")
                Picker("", selection: $vm.config.defaultProfileDirectory) {
                    ForEach(vm.profiles) { p in Text(p.name).tag(p.directory) }
                }.labelsHidden().onChange(of: vm.config.defaultProfileDirectory) { _, _ in vm.save() }
            }

            Divider()
            Text("Regeln (erste passende gewinnt)").font(.subheadline).foregroundStyle(.secondary)

            List {
                ForEach($vm.config.rules) { $rule in
                    HStack(spacing: 8) {
                        Picker("", selection: $rule.matchType) {
                            ForEach(MatchType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().frame(width: 90)
                        TextField("Muster", text: $rule.pattern).onSubmit { vm.save() }
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Picker("", selection: $rule.profileDirectory) {
                            ForEach(vm.profiles) { p in Text(p.name).tag(p.directory) }
                        }.labelsHidden().frame(width: 140)
                        Button(role: .destructive) { vm.deleteRule(rule) } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                }
                .onMove { from, to in vm.config.rules.move(fromOffsets: from, toOffset: to); vm.save() }
            }
            .frame(minHeight: 200)
            .onChange(of: vm.config.rules) { _, _ in vm.save() }

            HStack {
                Button("Regel hinzufügen") { vm.addRule() }
                Spacer()
                Button("Beenden") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 560)
    }
}
```

- [ ] **Step 3: Build prüfen**

Run: `swift build`
Expected: erfolgreicher Build.

- [ ] **Step 4: Commit**

```bash
git add Sources/DiaProfileRouterApp/SettingsView.swift Sources/DiaProfileRouterApp/ConfigViewModel.swift
git commit -m "feat(app): add configuration GUI (rules, default profile, set-default)"
```

---

## Task 14: App-Bundle + Info.plist + Registrierung

**Files:**
- Create: `Resources/Info.plist`
- Create: `scripts/make-app.sh`

- [ ] **Step 1: Info.plist** (LSUIElement + http/https-Handler)

```xml
<!-- Resources/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Dia Profile Router</string>
  <key>CFBundleDisplayName</key><string>Dia Profile Router</string>
  <key>CFBundleIdentifier</key><string>com.tora89.dia-profile-router</string>
  <key>CFBundleExecutable</key><string>DiaProfileRouterApp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>Web URL</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>CFBundleURLSchemes</key>
      <array><string>http</string><string>https</string></array>
    </dict>
  </array>
</dict>
</plist>
```

- [ ] **Step 2: Build-/Bundle-Skript**

```bash
# scripts/make-app.sh
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="build/Dia Profile Router.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$(swift build -c release --show-bin-path)/DiaProfileRouterApp" "$APP/Contents/MacOS/DiaProfileRouterApp"
# bei LaunchServices registrieren, damit der App in den Standardbrowser-Optionen erscheint
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo "Gebaut: $APP"
echo "Zum Installieren:  cp -R \"$APP\" /Applications/  &&  open \"/Applications/Dia Profile Router.app\""
```

- [ ] **Step 3: Ausführbar machen + bauen**

```bash
chmod +x scripts/make-app.sh
./scripts/make-app.sh
```
Expected: `build/Dia Profile Router.app` entsteht, kein Fehler.

- [ ] **Step 4: Commit**

```bash
git add Resources/Info.plist scripts/make-app.sh
git commit -m "build: app bundle assembly + LaunchServices registration"
```

---

## Task 15: End-to-End-Verifikation (manuell)

**Files:** keine — Verifikations-Checkliste.

- [ ] **Step 1: Installieren & starten**

```bash
cp -R "build/Dia Profile Router.app" /Applications/
open "/Applications/Dia Profile Router.app"
```
Expected: Menubar-Icon erscheint; Klick zeigt SettingsView mit deinen echten Profilnamen (Personal, Work, Client A, …).

- [ ] **Step 2: Standardbrowser setzen**

In der GUI „Als Standardbrowser setzen" klicken → Systemdialog bestätigen.
Expected: Label wechselt auf „Standardbrowser ✓".

- [ ] **Step 3: Berechtigungen erteilen**

Beim ersten Routing fragt macOS nach **Automation** (Dia steuern) und ggf. **Accessibility**
(für Menü-Fallback). In Systemeinstellungen → Datenschutz freigeben.

- [ ] **Step 4: Routing testen (Profilfenster offen)**

Eine Regel anlegen: `host` `example.com` → Client A. In Dia ein Client-A-Fenster offen halten.
Aus einer anderen App (z. B. Terminal) öffnen:
```bash
open "https://app.example.com/jira"
```
Expected: Link öffnet als neuer Tab im **Client A**-Fenster — lautlos.

- [ ] **Step 5: Routing testen (Fallback, kein Profilfenster)**

Das Community-Fenster in Dia schließen, Regel `host` `example.com` → Community anlegen, dann:
```bash
open "https://example.com/test"
```
Expected: UI-Automation öffnet ein neues Community-Fenster, Link landet dort.

- [ ] **Step 6: Default-Fallback testen**

Eine URL ohne passende Regel öffnen:
```bash
open "https://news.ycombinator.com"
```
Expected: Link landet im konfigurierten Default-Profil.

- [ ] **Step 7: Vollständige Tests grün**

Run: `swift test`
Expected: alle Unit-Tests (Core + App) PASS.

- [ ] **Step 8: Commit (falls Doku/Fixes anfielen)**

```bash
git add -A && git commit -m "docs: verification notes" || true
```

---

## Self-Review-Ergebnis

- **Spec-Abdeckung:** Regeltypen exakt/Präfix/Host/Wildcard (Task 4) ✓; Default-Profil (Task 4/7/13) ✓; Konfig-GUI für Base/Wildcard/konkrete URLs (Task 13) ✓; kein Picker, Voll-Automatik + UI-Automation-Fallback (Task 9) ✓; Default-Browser-Registrierung (Task 10) ✓; Finicky-Snippets geliehen: Wildcard (Task 3), Default-Browser-Ansatz (Task 10, modernisiert) ✓; Profile live aus Local State (Task 5) ✓; Fenster→Profil-Map (Task 6) ✓; Degradation (Task 11) ✓.
- **Platzhalter:** keine — jeder Code-Schritt enthält vollständigen Code.
- **Typ-Konsistenz:** `Profile.directory/name`, `Rule.matchType/pattern/profileDirectory`, `RuleEngine.profileDirectory(for:)`, `DiaController.open(url:profileDirectory:)`, `AppleScriptRunning.run(_:)`, `ProfileWindowMap.load/windows`, `ConfigStore.load/save/loadOrDefault` — über alle Tasks konsistent verwendet.
