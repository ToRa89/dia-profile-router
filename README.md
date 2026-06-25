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
        1. a window the app itself opened for that profile (cache) → reuse
        2. an open window whose ACTIVE tab routes (by your rules) to that profile → reuse
        3. otherwise: a new profile window via  File → New Window → "New <Profile> Window"
  → safety net (Dia unreachable): the link is handed to Dia via NSWorkspace, never lost
```

Background: Dia exposes **no** supported way to open a URL in a *specific* profile from the
outside (the CLI profile flag is rejected while Dia is running, there is no `dia://` routing
route, and AppleScript has no profile object). The router therefore composes the result from
supported pieces: AppleScript for tabs/window list, plus menu automation to spawn a new profile
window. A window's profile isn't queryable via any API — hence the heuristic based on tab URLs
and your own rules.

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

The app runs as a menu-bar item (no Dock icon).

## Setup

1. **Set as default browser** — in the menu-bar window, click "Set as default browser" and confirm the system dialog.
2. **Permissions** (one-time; persist afterwards thanks to the stable signature):
   - **Automation** → control Dia (allow the prompt on the first link)
   - **Accessibility** → for the menu automation that opens new profile windows
     (System Settings → Privacy & Security → Accessibility → add the app)
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
