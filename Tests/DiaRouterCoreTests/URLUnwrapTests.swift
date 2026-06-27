import Testing
import Foundation
@testable import DiaRouterCore

@Test func unwrapsEur01SafeLink() {
    let wrapped = URL(string:
        "https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fwww.porsche.com%2Fde%2F&data=05%7Cx")!
    #expect(URLUnwrap.staticUnwrap(wrapped) == URL(string: "https://www.porsche.com/de/")!)
}

@Test func unwrapsNam02SafeLink() {
    let wrapped = URL(string:
        "https://nam02.safelinks.protection.outlook.com/?url=https%3A%2F%2Fporsche.sharepoint.com%2Fsites%2Fx&data=x")!
    #expect(URLUnwrap.staticUnwrap(wrapped).host == "porsche.sharepoint.com")
}

@Test func unwrapsTeamsFileObjectUrl() {
    let wrapped = URL(string:
        "https://teams.microsoft.com/l/file/GUID?tenantId=t&objectUrl=https%3A%2F%2Fporsche.sharepoint.com%2Fsites%2Fx")!
    #expect(URLUnwrap.staticUnwrap(wrapped).host == "porsche.sharepoint.com")
}

@Test func unwrapsTeamsMeetingUrl() {
    let wrapped = URL(string:
        "https://teams.microsoft.com/l/meetingJoin/19:meeting_x?url=https%3A%2F%2Fexample.com%2Fmeeting")!
    #expect(URLUnwrap.staticUnwrap(wrapped).host == "example.com")
}

@Test func leavesNormalURLUnchanged() {
    let url = URL(string: "https://porsche.com/de/")!
    #expect(URLUnwrap.staticUnwrap(url) == url)
}

@Test func leavesTeamsURLWithoutTargetUnchanged() {
    // A Teams meeting-join URL that has no url= / objectUrl= param stays unchanged
    let url = URL(string: "https://teams.microsoft.com/l/meetingJoin/19:meeting_x?context=y")!
    #expect(URLUnwrap.staticUnwrap(url) == url)
}

@Test func httpRedirectHostsContainsExpectedEntries() {
    #expect(URLUnwrap.httpRedirectHosts.contains("go.microsoft.com"))
    #expect(URLUnwrap.httpRedirectHosts.contains("aka.ms"))
    #expect(!URLUnwrap.httpRedirectHosts.contains("porsche.com"))
}
