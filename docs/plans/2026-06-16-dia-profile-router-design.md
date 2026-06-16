# Dia Profile Router — Design

**Datum:** 2026-06-16
**Status:** Genehmigt (Brainstorming abgeschlossen)
**Ziel:** Eine macOS-App, die als Standardbrowser fungiert, jeden geöffneten Link gegen
konfigurierbare Regeln prüft und ihn im passenden **Dia-Profil** öffnet — analog zur
fehlenden „air control"-Profilwahl aus Arc. Voll automatisch (kein Picker im Normalfall),
mit konfigurierbarem Default-Profil als Fallback und einer GUI zur Regelpflege.

---

## 1. Problem & Kontext

Der Dia-Browser (The Browser Company, Chromium-/Arc-Boost-basiert) öffnet externe Links
immer im **zuletzt aktiven bzw. Default-Profil**. Wer täglich zwischen vielen Profilen
wechselt (Personal, Work, Community, Home, Client A, Client B, …), landet ständig im
falschen Profil. Ein Feature-Request bei Dia ist gestellt, aber nicht umgesetzt.

### Spike-Ergebnisse (hart verifiziert am 2026-06-16)

| Mechanismus | Ergebnis |
|---|---|
| CLI `--profile-directory` bei **laufendem** Dia | ❌ Eigene Single-Instance-Sperre (`ADKApplication`, „Only one instance … is already open") weist Zweitstart inkl. Argumente ab — kein Command-Line-Relay wie Standard-Chromium |
| CLI `--profile-directory` bei **kaltem** Dia | ✅ funktioniert (Standard-Chromium-Profilverzeichnisse) |
| `dia://`-Schema mit URL+Profil-Parameter | ❌ Nur interne Seiten (history, settings, bookmarks, assistant …), keine Routing-Route |
| AppleScript: Profil per **Name** ansteuern | ❌ Kein `profile`-/`space`-Objekt im `Dia.sdef` |
| AppleScript: Tab in **bestimmtem Fenster** anlegen | ✅ `make new tab at window id "<UUID>"` (Befehle: `make`, `close`, `focus`, `execute`) |
| Fenster → Profil zuordnen | ✅ **exakt** über `StorableProfileContainers.json` (`window._0` UUID → `profileID` = „Profile N"), korroboriert durch per-Profil `User Data/Profile N/Sessions/` |
| Eigener Command-Line-Switch | ❌ keiner vorhanden |
| Natives Default-Profil | ✅ `defaultProfileDirectoryBasename` / `setDefaultProfile` / `isDefaultProfile` |
| Profil-Menüpunkte (für UI-Automation) | ✅ „New Window – ‹Profilname›" (Format-String), „Switch to Profile 1…9", `openProfileSwitcher`, `ProfileSwitcherMenuBuilder` |

**Fazit:** Es gibt **keinen** unterstützten „öffne URL in Profil X"-Einzelbefehl von außen.
Aber aus unterstützten Bausteinen lässt sich das Ergebnis zuverlässig zusammensetzen:
AppleScript-Tab-in-Fenster + exakte Fenster→Profil-Zuordnung + Menü-Fallback zum Erzeugen
eines fehlenden Profilfensters.

### Profil-Inventar (aus `~/Library/Application Support/Dia/User Data/Local State`)

| Verzeichnis | Profilname |
|---|---|
| `Profile 4` | Personal |
| `Profile 5` | Home Automation |
| `Profile 6` | Work *(zuletzt genutzt)* |
| `Profile 7` | Community |
| `Profile 8` | Community B |
| `Profile 9` | Client B |
| `Profile 10` | Client A |

Profile werden **zur Laufzeit ausgelesen** — keine hartkodierten IDs.

---

## 2. Architektur

Standalone **Swift + SwiftUI Menubar-App** (`LSUIElement`, kein Dock-Icon), die sich als
http/https-Handler registriert. **Eigenständig** — borgt sich aber MIT-lizenzierte Snippets
aus [Finicky](https://github.com/johnste/finicky) (s. §6).

```
Klick auf Link (irgendeine App)
        │  macOS routet an unseren registrierten http/https-Handler
        ▼
[1] AppDelegate.application(_:open:)  — empfängt URL(s)
        ▼
[2] RuleEngine.match(url) -> ProfileID?     (erste passende Regel; sonst Default-Profil)
        ▼
[3] DiaController.open(url, profileDirectory: P, profiles, belongsToTargetProfile)
        │  (In-Memory-Cache: profileDir → von uns erzeugte Fenster-UUID)
        │
        ├─ Cache hat lebendes Fenster für P?  (gegen `id of every window` geprüft)
        │     └─ ja  → make new tab at window id <UUID> with {URL}   ✅ Wiederverwendung
        │
        ├─ Offenes Fenster, dessen AKTIVE Tab-URL per Nutzer-Regel auf P matcht?
        │     └─ ja  → dort Tab öffnen + cachen  ✅ Wiederverwendung auch MANUELL geöffneter Fenster
        │
        ├─ sonst: Menü-Automation (System Events) klickt
        │         File → New Window → „New ‹P-Name› Window"  (2 Ebenen, truncation-tolerant)
        │         → pollt ~2 s auf neue Fenster-UUID → cached sie → make new tab darin
        │
        ├─ Profil unbekannt / Menüeintrag fehlt → make new tab at front window
        │
        └─ Fehler/Dia nicht erreichbar → NSWorkspace.open(url) an Dia, Link geht NIE verloren
```

> **Heuristik zur Wiederverwendung manuell geöffneter Fenster (implementiert):** Da das Profil
> eines Fensters über keine API abfragbar ist, gilt ein offenes Fenster als zu Profil P gehörig,
> wenn seine **aktive Tab-URL** per `RuleEngine.matchedRule` (expliziter Regel-Treffer, nicht
> Default-Fallback) auf P zeigt. Das nutzt die Nutzer-Regeln wieder, braucht keinen fragilen
> SNSS-Parser und greift nicht versehentlich auf Default-Fenster zu. Grenze: ein P-Fenster,
> dessen aktiver Tab gerade eine nicht-passende Seite zeigt, wird nicht erkannt → dann neues Fenster.

### Warum dieser Mechanismus (korrigiert nach Live-Verifikation 2026-06-16)

- **Verworfen:** „Fenster→Profil aus `StorableProfileContainers.json`". Diese Datei ist
  **stale** (wird selten geschrieben; in der Praxis Monate alt) und enthält **keine** der
  Live-AppleScript-Fenster-UUIDs — die UUIDs existieren nur im Speicher und stehen in keiner
  Datei. Der dateibasierte Map-Pfad greift zur Laufzeit nie.
- **Profil-Zuordnung bestehender Fenster ist über keine API abfragbar.** Daher merkt sich der
  Router die Fenster, **die er selbst** via Menü erzeugt (Cache `profileDir → UUID`), prüft
  deren Lebendigkeit gegen `id of every window` und verwendet sie wieder.
- **Zuverlässiger Profil-Treffer** kommt aus Dias Menü `File → New Window → „New ‹Profil›
  Window"` (ein Eintrag je Profil, live bestätigt). Erfordert **Accessibility**-Recht.
- **Truncation-tolerant:** lange Profilnamen werden im Menü abgeschnitten
  (z. B. „New Home Automati… Window") → Matching per Präfix.
- **Heuristische Wiederverwendung manuell geöffneter Fenster** ist **implementiert** — aber
  über die **aktive Tab-URL + Nutzer-Regeln** (s. Diagramm oben), NICHT über Chromium-Sessions
  (die sind Verlaufs-Obermengen und bräuchten einen fragilen SNSS-Parser).

---

## 3. Regel-Modell & Konfiguration

### Regeltypen (Reihenfolge = Priorität, erste Treffer gewinnt)

| Typ | Beispiel | Match |
|---|---|---|
| Exakte URL | `https://app.example.net/selfservices/` | voller String-Vergleich (nach Normalisierung) |
| Basis-URL (Host/Pfad-Präfix) | `https://team.example.org/sites/Docs` | Host + Pfad-Präfix |
| Wildcard | `*.example.com`, `*/sites/Docs*` | portierte Finicky-Wildcard-Logik |
| Host | `client-b.example.net` | Host inkl. Subdomains |

- **Default-Profil**: globaler Fallback bei keinem Treffer (frei wählbar).
- **Regeln immutabel verwaltet** (neue Objekte statt In-Place-Mutation).

### Konfig-UI (SwiftUI)

- Liste der Regeln (Pattern → Profil), per Drag sortierbar.
- „Regel hinzufügen": Pattern-Typ wählen, Pattern eingeben, Profil aus Dropdown
  (Profile live aus `Local State`).
- Default-Profil-Auswahl.
- Button „Als Standardbrowser setzen" (→ `LSSetDefaultHandlerForURLScheme`).
- Berechtigungs-Status & geführtes Setup (Automation, Accessibility).
- Optional/V2: „Letzte 20 geroutete Links" — pro Eintrag „Regel daraus anlegen".

### Persistenz

- JSON unter `~/.config/dia-router/config.json` (Regeln, Default-Profil, Optionen).
- `Codable`-Structs, atomare Writes.

---

## 4. Komponenten

| Komponente | Verantwortung | Testbar |
|---|---|---|
| `AppDelegate` | http/https-Empfang (`application:openURLs:`), Bootstrapping | Integration |
| `RuleEngine` | reine Funktion `URL -> ProfileID?` (Matcher + Wildcard) | **Unit (Kern)** |
| `Wildcard` | portierte Finicky-Wildcard-Logik | **Unit** |
| `ProfileStore` | liest/parst Dia `Local State` → `[Profile(dir, name)]` | Unit (Fixtures) |
| `ProfileWindowMap` | Fenster-UUID → profileID aus `StorableProfileContainers.json` + `Sessions/` | Unit (Fixtures) |
| `DiaController` | AppleScript-Aufrufe, Menü-Fallback, Fehler-Degradation | manuell + Smoke |
| `ConfigStore` | Laden/Speichern der Config (immutabel) | Unit |
| `DefaultBrowser` | Registrierung/Abfrage (ObjC-Bridge, von Finicky geliehen) | manuell |
| `SettingsView` (SwiftUI) | Konfig-GUI | visuell |

---

## 5. Fehlerbehandlung, Berechtigungen, Edge Cases

### Berechtigungen (einmaliges, in der UI geführtes Setup)
- **Automation** (AppleEvents → Dia) — für `osascript`/`make new tab`.
- **Accessibility** — für den Menü-Fallback (System Events).
- **Standardbrowser-Registrierung** — via `LSSetDefaultHandlerForURLScheme`.

### Degradation (Link darf nie verloren gehen)
1. AppleScript-Fehler / Dia antwortet nicht → `NSWorkspace.open(url)` (Default-Profil).
2. `StorableProfileContainers.json`-Format unbekannt → Fenster-Map leer → Fallback greift.
3. Menü-Eintrag „New Window – ‹P›" nicht gefunden → tolerantes Matching per Profilname,
   sonst Default-Profil + Notification.

### Edge Cases
- Dia gar nicht gestartet → kalt mit `--profile-directory` starten ist hier erlaubt
  (Singleton blockt nur bei laufender Instanz).
- Mehrere Fenster pro Profil → erstes/aktivstes Fenster des Profils wählen.
- URL-Normalisierung vor Matching (Shortener-Auflösung optional/V2).

### Tests
- `RuleEngine` & `Wildcard`: breite Unit-Abdeckung (Host, Präfix, Wildcard, Negativfälle).
- `ProfileStore` & `ProfileWindowMap`: Fixtures echter Dia-Dateien.
- `DiaController`: AppleScript-Smoke-Test gegen echte Profile (manuell), Routing-Log zur
  Verifikation.

---

## 6. Geliehen aus Finicky (MIT)

| Baustein | Quelle | Verwendung |
|---|---|---|
| Default-Browser-Registrierung | `apps/finicky/src/browser.m` (`LSSetDefaultHandlerForURLScheme`, `URLForApplicationToOpenURL`) | ObjC-Bridge ~40 Zeilen übernehmen |
| http/https `CFBundleURLTypes` | `apps/finicky/assets/Info.plist` | Info.plist-Muster |
| Wildcard-Matching | `packages/config-api/src/wildcard.ts` (+ `wildcard.test.ts`) | nach Swift portieren |
| Opener-Erkennung | `OpenUrlOptions.opener` | Bonus / V2 (Regel-Dimension „welche App öffnete") |

**Lizenzhinweis:** Finicky ist MIT-lizenziert — geliehene Teile mit Quell-/Copyright-Vermerk
kennzeichnen, MIT-Lizenztext beilegen.

> Verworfen: Finicky als Unterbau hindurchrouten — sein Launcher ruft ausschließlich
> macOS `open` und kann unsere AppleScript-Logik nicht ausführen; sein `profile:`-Feature
> nutzt `open -n -a Dia --args --profile-directory` und läuft gegen Dias Singleton-Sperre.

---

## 7. Bekannte Risiken (ehrlich)

- **AppleScript-Fensteransteuerung**: stabil/unterstützt — geringes Risiko.
- **`StorableProfileContainers.json`-Format**: könnte sich mit Dia-Updates ändern →
  degradiert sauber auf Default-Profil.
- **Menü-Fallback**: Menütitel könnte sich ändern → tolerantes Matching per Profilname,
  sonst Default + Hinweis.
- **macOS-Berechtigungen**: erfordern einmalige Nutzerfreigabe; ohne Accessibility nur
  Primärweg + Default-Fallback (Fenster-Erzeugung entfällt).

---

## 8. Nicht im Scope (YAGNI / V2)

- Andere Browser als Dia.
- Shortener-Auflösung / URL-Rewrite.
- Sync der Config über Geräte.
- Opener-basierte Regeln (App, die den Link öffnete) — vorbereitet, später.
