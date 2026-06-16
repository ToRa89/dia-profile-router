// Sources/DiaProfileRouterApp/AppDelegate.swift
import AppKit
import DiaRouterShell

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    let router = Router()

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
        router.route(url)
    }
}
