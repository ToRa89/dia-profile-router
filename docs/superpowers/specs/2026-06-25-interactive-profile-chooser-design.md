# Interaktiver Profil-Chooser + Regel-Lernen — Design

**Datum:** 2026-06-25
**Status:** freigegeben (bereit für Implementierungsplan)

## Problem / Motivation

Der Router kann ein Dia-Fenster keinem Profil zuordnen — Dia bietet dafür keine API.
Er rät heute über Tab-URLs in mehreren Stufen. Die schwächste Stufe („*irgendein* Tab im
Fenster passt zum Zielprofil", Pfad 2c in `DiaController.open`) ist unzuverlässig:

- Tab-Vorkommen ≠ Fenster-Profil. Große, langlebige Fenster „matchen" schnell mehrere Profile.
- Ein einmal falsch geratenes Fenster wird **gecacht** → alle weiteren Links dieses Profils
  landen per Cache-Schnellpfad dauerhaft falsch, bis das Fenster stirbt oder die App neu startet.

Diagnose (24.06.2026) hat belegt, was **nicht** die Ursache ist:

- **Accessibility/Bedienungshilfen** funktionieren — im sauberen Test las die App per System
  Events das Menü, klickte den Profilpunkt und erzeugte ein korrektes neues Profilfenster
  (TCC-Request ohne `-1719`/`-25211`). Das Neuerteilen der Berechtigung war wirkungslos, weil
  es nie die Ursache war.
- **Signatur/TCC-Reset** — beide App-Kopien tragen identische, stabile Signatur (Cert-Leaf
  `0563cfdb…`); kein rebuild-bedingter Rechteverlust.
- **Automation** (Apple Events an Dia) funktioniert.

Beobachteter Auslöser des Rückfalls: Stufe 2b („**aktives** Tab passt", das stärkste Signal)
ist tot, sobald der Nutzer in seinen Fenstern auf Nicht-Regel-Seiten surft (mollie,
yogi-manager, paperless) bzw. ein Fenster gar kein aktives Tab-URL liefert (`missing value`).
Dann fällt alles auf 2c zurück und rät.

## Ziel

Statt zu raten: Bei Unsicherheit **fragen** und aus der Antwort **lernen**.

- Trifft eine Regel → still ins richtige Profil routen (kein Dialog).
- Trifft **keine** Regel → eigenes Chooser-Fenster: Profil wählen, optional als Regel merken.
- Platzierung im Zielprofil nur über **verlässliche** Signale (Cache, aktiv-Tab, neues Fenster);
  die unzuverlässige „irgendein-Tab"-Stufe entfällt.
- Entscheidungs-Logging, damit künftige Rückfälle in einer `log show`-Abfrage sichtbar sind.

## Nicht-Ziele (YAGNI)

- Keine echte Dia-Profil-API (existiert nicht).
- Keine eTLD+1-/Public-Suffix-Logik (würde `*.sharepoint.com`-Tenants fälschlich verschmelzen).
- Kein Persistieren des In-Memory-Window-Caches über App-Neustarts (separate spätere Idee).
- Kein UI-Unit-Test des AppKit-Fensters.

## Entscheidungen (mit Nutzer abgestimmt)

| Frage | Entscheidung |
|---|---|
| Wann erscheint der Chooser? | Nur wenn **keine Regel** passt (Treffer routen still). |
| Chooser-Oberfläche | Eigenes, zentriertes Fenster mit einem Button pro Profil. |
| Gemerktes Regel-Muster | `matchType host`, Muster = Host ohne führendes `www.`, **editierbar**. |
| `*.sharepoint.com` | Bleibt voller Host (`porsche.sharepoint.com`) — Tenants getrennt. |
| Abbruch des Choosers | Öffnet im **Default-Profil** (Einstellung bleibt als Sicherheitsnetz). |
| „Als Regel merken"-Häkchen | Standard **AUS**. |
| Platzierung nach Profilwahl | Cache → aktiv-Tab → neues Profilfenster (kein „irgendein-Tab"). |
| Mehrere needsChoice-Links | Serialisiert, FIFO; ein Fenster nach dem anderen. |

## Architektur (Ansatz 2: Entscheidungs-Schicht + injizierter Chooser)

Reine Entscheidung/Regel-Logik in **Core** (unit-testbar, keine UI). **Shell** orchestriert und
spricht AppleScript. **App** liefert nur das konkrete Fenster. Der Chooser ist über ein Protokoll
austauschbar (wie das bestehende `AppleScriptRunning`) → Router/Decision voll testbar ohne UI.

### Ablauf

```
GetURL  →  Router.route(url)            // wird async
  1. RuleEngine.decide(url):
       • Regel trifft → .matched(profileDir)   → platzieren
       • kein Treffer → .needsChoice(host)     → Chooser
  2. ProfileChooser.choose(...):
       • Profil gewählt → (optional Regel schreiben) → platzieren im gewählten Profil
       • abgebrochen    → platzieren im Default-Profil
  3. DiaController.open: Cache → aktiv-Tab → neues Profilfenster → Front-Fallback
       (mit Logging je Stufe)
```

### Bausteine

| Datei | Modul | Status | Aufgabe |
|---|---|---|---|
| `RouteDecision.swift` | Core | neu | `enum RouteDecision { case matched(String); case needsChoice(host: String) }`; `RuleEngine.decide(for:) -> RouteDecision` |
| `RuleSuggestion.swift` | Core | neu | `hostPattern(for url:) -> String` (Host, lowercased, ohne `www.`); `appended(_ rule: Rule, to: RouterConfig) -> RouterConfig` (Dedup) |
| `ProfileChooser.swift` | Shell | neu | `protocol ProfileChooser: Sendable { func choose(url: URL, profiles: [Profile], defaultDirectory: String) async -> ChooserResult? }`; `struct ChooserResult { let profileDirectory: String; let rememberPattern: String? }` |
| `RoutingLog.swift` | Shell | neu | `os.Logger`-Wrapper, Subsystem `com.tora89.dia-profile-router`, Category `routing` |
| `ChooserWindowController.swift` | App | neu | AppKit-`NSWindowController` mit eingebettetem SwiftUI-Chooser; erfüllt `ProfileChooser`; serialisiert (FIFO) |
| `ChooserView.swift` | App | neu | SwiftUI-View: URL, Profil-Buttons (Grid), „merken"-Häkchen + editierbares Host-Feld, Abbrechen |
| `Router.swift` | Shell | ändern | `route` → `async`; `decide` + injizierter `ProfileChooser`; schreibt ggf. Regel via `ConfigStore`; loggt |
| `DiaController.swift` | Shell | ändern | 2c-Block + `windowsWithAllTabURLs()` entfernen; Logging je Stufe |
| `AppDelegate.swift` | App | ändern | injiziert Prod-`ProfileChooser` in `Router`; `handleGetURL` ruft `route` in `Task { @MainActor }` |

## Komponenten-Details

### RouteDecision / decide (Core)
`decide(for url:)` = `matchedRule(for:) != nil` → `.matched(rule.profileDirectory)`,
sonst `.needsChoice(host: URLNormalize.host(url))`. `profileDirectory(for:)` bleibt für
Bestandscode erhalten.

### RuleSuggestion (Core)
- `hostPattern(for url:)`: `URLNormalize.host(url)`; führendes `www.` entfernen; leeres Ergebnis → `nil`.
- `appended(_:to:)`: existiert `.host`-Regel mit gleichem `pattern` (case-insensitive) →
  deren `profileDirectory` aktualisieren; sonst Regel **anhängen**. Liefert neue `RouterConfig`
  (immutabel).

### ProfileChooser (Shell, Protokoll) + Prod-Impl (App)
- `ChooserResult.rememberPattern == nil` → nicht merken. Rückgabe `nil` → Abbruch.
- Prod-Impl (`ChooserWindowController`):
  - `NSApp.activate(ignoringOtherApps: true)`, Fenster zentriert + Key-Window.
  - Default-Profil-Button hat Tastatur-Fokus (Enter = Default); Esc = Abbrechen.
  - **Serialisierung:** ein `@MainActor`-FIFO; ist bereits ein Chooser offen, reihen sich weitere
    `choose`-Aufrufe ein und werden nacheinander abgearbeitet.

### Router (Shell)
```
func route(_ url: URL) async {
  config = ConfigStore.loadOrDefault(...)         // wie heute: pro Link frisch
  switch RuleEngine(config).decide(for: url) {
    case .matched(dir): place(url, dir, source:.rule)
    case .needsChoice(host):
      if let r = await chooser.choose(url, profiles, config.defaultProfileDirectory) {
        if let pat = r.rememberPattern, !pat.isEmpty {
          // read-modify-write FRISCH laden (nicht das `config` von oben), sonst Lost-Update
          // bei mehreren needsChoice-Links nacheinander
          let fresh = ConfigStore.loadOrDefault(...)
          let newCfg = RuleSuggestion.appended(Rule(.host, pat, r.profileDirectory), to: fresh)
          try? ConfigStore.save(newCfg, ...)       // vor dem Platzieren; Fehler → nur loggen
        }
        place(url, r.profileDirectory, source:.chooser)
      } else {
        place(url, config.defaultProfileDirectory, source:.cancelDefault)
      }
  }
}
```
`place` kapselt `belongs`-Closure + `DiaController.open` + Logging (heutiger try/catch-Fallback
`openInDiaDirectly` bleibt).

### DiaController.open (Shell)
Reihenfolge nach Fix: (1) Cache-Treffer (lebt) → openTab; (2) aktiv-Tab-Heuristik → openTab + cachen;
(3) Profilname auflösen → Menüpunkt → neues Fenster → openTab + cachen; (4) Front-Fenster-Fallback.
**Entfernt:** Block „all-tabs" + Methode `windowsWithAllTabURLs()`. Logging je gewählter Stufe inkl.
Fenster-UUID.

### Logging (Shell, os.Logger)
- `Router`: je Link eine `.info`-Zeile — URL, Entscheidung, Quelle (`rule`/`chooser`/`cancelDefault`), Zielprofil.
- `DiaController.open`: gewählte Stufe (`cache`/`activeTab`/`newWindow`/`frontFallback`) + UUID (+ Menüpunkt).
- Abfrage künftig: `log show --predicate 'subsystem == "com.tora89.dia-profile-router"' --info`.

## Fehlerbehandlung (Link nie verlieren)
- Config-Schreibfehler beim Merken → loggen, trotzdem ins gewählte Profil platzieren.
- Chooser nicht darstellbar/Fehler → loggen, ins Default-Profil platzieren.
- `DiaController`-Fehler → bestehender `openInDiaDirectly`-Fallback.

## Threading
- `route` ist `async`, läuft `@MainActor` (DiaController ist bereits `@MainActor`).
- `AppDelegate.handleGetURL` startet `Task { @MainActor in await router.route(url) }`.
- Chooser-FIFO auf `@MainActor` → keine überlappenden Fenster.

## Tests
- **Core:** `decide` (Treffer/kein Treffer); `hostPattern` (www-Strip, Groß/Klein,
  `porsche.sharepoint.com` bleibt ganz, leerer Host → nil); `appended` (Neu-Anhängen + Dedup-Update).
- **Shell (Mock-`ProfileChooser`):**
  (a) Regel trifft → Chooser wird **nicht** gerufen, Routing ins Regel-Profil;
  (b) kein Treffer + `rememberPattern` → Regel in Config geschrieben + Routing ins gewählte Profil;
  (c) Abbruch (`nil`) → Routing ins Default-Profil.
- **Shell:** aktualisierte `DiaController`-Tests — „nur Hintergrund-Tab passt → **neues** Fenster"
  ersetzt den alten 2c-Reuse-Test.
- **UI:** Chooser-Fenster nur über Protokoll-Mock; kein AppKit-Unit-Test.

## Auswirkungen auf bestehende Doku
- `README.md`: Abschnitt „How it works" (Reuse-Stufen) + „Limitations" anpassen; Chooser/Lernen
  beschreiben. (Im Implementierungsplan.)
