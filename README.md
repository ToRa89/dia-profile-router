<p align="center">
  <img src="assets/logo.svg" width="120" alt="Dia Profile Router logo">
</p>

<h1 align="center">Dia Profile Router</h1>

<p align="center">Open every link in the <strong>right Dia profile</strong> — automatically, by per-URL rules.</p>

---

The [Dia browser](https://www.diabrowser.com/) always opens external links in the last-active
profile. If you work across many profiles (personal, work, client A, client B …) you constantly
end up in the wrong one. Dia Profile Router registers itself as your default browser, matches each
incoming link against your rules, and opens it in the matching profile — no picker, no fuss.

> A personal macOS tool. Not a Developer-ID / App Store build.

## How it works

```
Link click (any app)
  → macOS hands the URL to Dia Profile Router (registered http/https handler)
  → rule match  →  target profile  (route silently)
  → no rule     →  ask which profile (chooser); optionally remember it as a host rule
  → the link lands in the profile via the first of:
        1. Dia's profile API: the tab is created in  profile "<Name>"  and focused
           (window preference: one already showing that profile, else the frontmost)
        2. legacy path (older Dia builds): reuse a cached/heuristically matched window,
           else a new profile window via  File → New Window → "New <Profile> Window"
        3. otherwise: the front window
  → safety net (Dia unreachable): the link is handed to Dia via NSWorkspace, never lost
```

Background: current Dia builds model a profile as a *space of tabs inside a window* and expose it
in their AppleScript dictionary (`profile` class with `name`, plus `focus` / `move`). The router
addresses the target **by profile name** — never by menu or list position, which shifts as soon as
a profile is added, removed, or reordered — and needs no UI scripting for this path. Older builds
created one window per profile and had no profile object; that path is kept as a fallback and
relies on menu automation plus a tab-URL heuristic.

## Requirements

- macOS 13+
- [Dia](https://www.diabrowser.com/) installed, with profiles set up
- Swift 6 / Xcode toolchain (to build)

## Build & install

```bash
# one-time: set up a stable signing identity (otherwise macOS resets permissions on every build)
# → see docs/SIGNING.md

./scripts/make-app.sh
cp -R "build/Dia Profile Router.app" /Applications/
open "/Applications/Dia Profile Router.app"
```

The app runs as a menu-bar item; its icon opens a small menu with "Einstellungen …" and
"Beenden". It has no Dock icon at rest — while the settings window or a chooser is open it
temporarily gets one, so neither can get lost behind the app you were working in. The chooser
additionally floats above other apps, since it blocks a link from being routed.

## Setup

1. **Set as default browser** — in the menu-bar window, click "Set as default browser" and confirm the system dialog.
2. **Permissions** (one-time; persist afterwards thanks to the stable signature):
   - **Automation** → control Dia (allow the prompt on the first link)
   - **Accessibility** → only needed for the legacy menu automation (older Dia builds);
     the profile API path works without it. "Bedienungshilfen erlauben" triggers the system
     prompt, which registers the app in System Settings → Privacy & Security → Accessibility —
     so you only flip the switch there instead of adding the binary via "+".
3. **Rules & default profile** — manage them in the menu-bar window.

## Configuration

Profiles are read automatically from Dia's `Local State` (real profile names appear in the UI).

**Rule types** (first matching rule wins; reorder by drag):

| Type | Example | Matches |
|---|---|---|
| `host` | `example.com` | the host and all subdomains (`*.example.com`) |
| `prefix` | `team.example.org/sites/Docs` | host + path prefix |
| `wildcard` | `*client-b*`, `*/sites/Docs*` | `*` = any run of characters; without `/` matches the host, with `/` matches host+path |
| `exact` | `https://app.example.net/login` | exact (normalized) comparison |

- **Default profile**: fallback when no rule matches.
- Persistence: `~/.config/dia-router/config.json` (re-read by the app on every link).

## Limitations

- Window reuse relies on a window's ACTIVE tab matching one of your rules. If a profile's window
  is currently showing an off-rule page, the router opens a fresh profile window rather than
  guessing from background tabs (which previously caused links to land in the wrong profile).
- Dia is the only supported target browser.

## Project layout

```
Sources/DiaRouterCore       – pure logic (models, rule engine, wildcard, profile/config stores)
Sources/DiaRouterShell      – AppKit/AppleScript side (routing controller, default-browser bridge)
Sources/DiaProfileRouterApp – menu-bar app (@main) + config GUI
docs/                       – design, implementation plan, signing guide
```

Docs: [Design](docs/plans/2026-06-16-dia-profile-router-design.md) ·
[Signing](docs/SIGNING.md) · [Plan](docs/superpowers/plans/2026-06-16-dia-profile-router.md)

## Tests

```bash
swift test
```

## License

[MIT](LICENSE). The wildcard-matching logic is ported from
[Finicky](https://github.com/johnste/finicky) (MIT), which also inspired the default-browser-router
concept — see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). Default-browser registration here
uses Apple's native `NSWorkspace` API (no Finicky code).
