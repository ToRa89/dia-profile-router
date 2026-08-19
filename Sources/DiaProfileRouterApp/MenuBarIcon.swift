// Sources/DiaProfileRouterApp/MenuBarIcon.swift
import AppKit

/// The menu-bar item's icon: a simplified, monochrome variant of the app icon (see
/// assets/menubar-icon.svg), bundled as MenuBarIcon.png/@2x by scripts/make-app.sh.
enum MenuBarIcon {
    /// Template image so macOS tints it for light and dark menu bars. `nil` when the bundled
    /// asset is unavailable (e.g. running the executable outside the .app bundle), so callers
    /// can fall back to an SF Symbol instead of showing an empty menu-bar slot.
    static let image: NSImage? = {
        guard let image = NSImage(named: "MenuBarIcon") else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
}
