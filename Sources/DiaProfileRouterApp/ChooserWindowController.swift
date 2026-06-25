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
