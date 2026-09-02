// Tests/DiaRouterShellTests/LocalFileRoutingTests.swift
import Testing
import Foundation
@testable import DiaRouterShell

@Test func fileURLIsNotSentThroughTheHTTPResolver() async {
    // resolve() must never touch the network for file URLs — it returns them untouched.
    let url = URL(fileURLWithPath: "/tmp/a.html")
    #expect(await URLResolver.resolve(url) == url)
}
