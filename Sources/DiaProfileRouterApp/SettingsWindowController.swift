// Sources/DiaProfileRouterApp/SettingsWindowController.swift
import AppKit
import SwiftUI
import DiaRouterShell

/// Shows the settings in a real window instead of a menu-bar popover.
///
/// A popover closes the moment another app takes focus — it cannot be kept on screen, and a Dock
/// icon would have nothing to point at (SwiftUI also does not report that dismissal reliably, so
/// the icon would stick around forever). A window stays until it is closed, shows up in the Dock
/// and the app switcher while it is open, and can be raised from there.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if let window {
            raise(window)   // already open → don't stack a second copy
            return
        }
        let win = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        win.title = "Dia Profile Router"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.isReleasedWhenClosed = false
        win.center()
        win.delegate = self
        window = win

        DockPresence.shared.windowWillShow()
        raise(win)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        DockPresence.shared.windowDidClose()
    }

    private func raise(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
