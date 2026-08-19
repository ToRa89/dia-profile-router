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
    /// Dock icon while a chooser is on screen, so it cannot get lost behind the app the link
    /// was clicked in (the router itself is a menu-bar-only LSUIElement app).
    private let dock = DockPresence()

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
            var delegate: WindowCloseDelegate?

            let finish: (ChooserResult?) -> Void = { [dock] result in
                guard !didResume else { return }
                didResume = true
                delegate = nil  // release delegate after use
                window?.close()
                dock.windowDidClose()
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

            delegate = WindowCloseDelegate(onClose: { finish(nil) })
            win.delegate = delegate

            // Float above the app the link was clicked in. macOS may refuse to activate a
            // background app at all, and then a normal-level window would sit behind that app
            // with nothing but the Dock icon hinting at it.
            win.level = .floating

            // Dock icon BEFORE activating — the policy switch is what makes the activation
            // request stick. AppKit needs one runloop turn to apply the new policy, so the
            // activation is asked for afterwards; orderFrontRegardless shows the window even
            // if macOS denies activation.
            dock.windowWillShow()
            win.orderFrontRegardless()
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                win.makeKeyAndOrderFront(nil)
            }
        }
    }
}

// MARK: - Private helpers

private final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
