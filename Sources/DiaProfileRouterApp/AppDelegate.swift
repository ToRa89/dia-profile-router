// Sources/DiaProfileRouterApp/AppDelegate.swift
import AppKit
import DiaRouterShell
import DiaRouterCore

// TODO(Task 5): Replace with the real ProfileChooserWindow implementation.
@MainActor
private final class NullChooser: ProfileChooser {
    func choose(url: URL, profiles: [Profile], defaultDirectory: String) async -> ChooserResult? { nil }
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    // TODO(Task 5): Inject real UI chooser here.
    let router = Router(chooser: NullChooser())

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI's MenuBarExtra lifecycle does NOT deliver http(s) URLs to
        // `application(_:open:)`, so we register the classic GetURL Apple Event handler.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(event:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleGetURL(event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: s) else { return }
        Task { await router.route(url) }
    }
}
