// Sources/DiaRouterShell/DockPresence.swift
import AppKit

/// Gives the app a Dock icon for as long as a chooser window is on screen.
///
/// The router runs as an `LSUIElement` (menu-bar) app, and macOS lets an accessory app raise
/// itself only conditionally — so the chooser could end up behind the app the link was clicked in,
/// with nothing in the Dock to point at it. Switching to `.regular` while a chooser is visible
/// puts it in the Dock and makes activation reliable; closing the last chooser returns the app to
/// `.accessory` so it stays out of the Dock and the app switcher the rest of the time.
///
/// The policy call is injected so the counting behaviour can be tested without a running NSApp.
@MainActor
public final class DockPresence {
    /// Shared by every window that should put the app in the Dock (chooser, settings), so the
    /// icon disappears only once the last one is gone.
    public static let shared = DockPresence()

    public typealias PolicySetter = (NSApplication.ActivationPolicy) -> Void

    private let setPolicy: PolicySetter
    private var visibleWindows = 0

    public init(setPolicy: @escaping PolicySetter = { NSApp.setActivationPolicy($0) }) {
        self.setPolicy = setPolicy
    }

    /// Call right before a chooser window is ordered front.
    public func windowWillShow() {
        visibleWindows += 1
        guard visibleWindows == 1 else { return }   // already visible → no policy churn
        setPolicy(.regular)
    }

    /// Call once per closed chooser window. Unbalanced calls are ignored, so a window that
    /// reports both an explicit decision and `windowWillClose` cannot hide the Dock icon early.
    public func windowDidClose() {
        guard visibleWindows > 0 else { return }
        visibleWindows -= 1
        guard visibleWindows == 0 else { return }
        setPolicy(.accessory)
    }
}
