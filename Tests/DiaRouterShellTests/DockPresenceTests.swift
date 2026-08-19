// Tests/DiaRouterShellTests/DockPresenceTests.swift
import Testing
import AppKit
@testable import DiaRouterShell

@MainActor
private final class PolicySpy {
    var applied: [NSApplication.ActivationPolicy] = []
    func make() -> DockPresence { DockPresence { self.applied.append($0) } }
}

@Test @MainActor func showsDockIconWhileAChooserWindowIsVisible() {
    let spy = PolicySpy()
    let dock = spy.make()

    dock.windowWillShow()
    #expect(spy.applied == [.regular])

    dock.windowDidClose()
    #expect(spy.applied == [.regular, .accessory])
}

@Test @MainActor func keepsDockIconWhileAnyWindowRemains() {
    let spy = PolicySpy()
    let dock = spy.make()

    dock.windowWillShow()
    dock.windowWillShow()          // second chooser queued/open at the same time
    #expect(spy.applied == [.regular])   // no redundant policy churn

    dock.windowDidClose()
    #expect(spy.applied == [.regular])   // one window still on screen → icon stays

    dock.windowDidClose()
    #expect(spy.applied == [.regular, .accessory])
}

@Test @MainActor func ignoresUnbalancedCloseCalls() {
    let spy = PolicySpy()
    let dock = spy.make()

    dock.windowDidClose()          // close without a preceding show must not hide anything
    #expect(spy.applied.isEmpty)

    dock.windowWillShow()
    dock.windowDidClose()
    dock.windowDidClose()          // double close (cancel + windowWillClose) stays balanced
    #expect(spy.applied == [.regular, .accessory])
}
