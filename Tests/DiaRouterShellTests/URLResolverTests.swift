// Tests/DiaRouterShellTests/URLResolverTests.swift
import Testing
import Foundation
@testable import DiaRouterShell
import DiaRouterCore

// Static-path tests (no network needed)

@Test func resolverUnwrapsSafeLinksStatically() async {
    let wrapped = URL(string:
        "https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fporsche.com%2Fde%2F&data=x")!
    let result = await URLResolver.resolve(wrapped)
    #expect(result.host == "porsche.com")
}

@Test func resolverReturnsOriginalForUnknownHost() async {
    // Not a SafeLink, not a redirect host → returned unchanged, no HTTP call attempted
    let url = URL(string: "https://porsche.com/de/")!
    let result = await URLResolver.resolve(url)
    #expect(result == url)
}

@Test func resolverReturnsOriginalForTeamsLinkWithoutTargetParam() async {
    // Teams URL without url= or objectUrl= → static unwrap returns original → not in httpRedirectHosts → unchanged
    let url = URL(string: "https://teams.microsoft.com/l/meetingJoin/19:x?context=y")!
    let result = await URLResolver.resolve(url)
    #expect(result == url)
}
