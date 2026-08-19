// Tests/DiaRouterShellTests/AccessibilityPermissionTests.swift
import Testing
@testable import DiaRouterShell

@Test func skipsSettingsPaneWhenAccessIsAlreadyTrusted() {
    var promptCalls = 0
    var settingsOpened = false

    let granted = AccessibilityPermission.request(
        promptForTrust: { promptCalls += 1; return true },
        openSettingsPane: { settingsOpened = true })

    #expect(granted)
    #expect(promptCalls == 1)
    #expect(!settingsOpened)      // nothing to grant → don't yank the user into System Settings
}

@Test func promptsBeforeOpeningSettingsSoTheAppIsListed() {
    var order: [String] = []

    let granted = AccessibilityPermission.request(
        promptForTrust: { order.append("prompt"); return false },
        openSettingsPane: { order.append("settings") })

    #expect(!granted)
    // The prompt is what registers the app in the Accessibility list, so it has to run BEFORE
    // the pane opens — otherwise the user stares at a list without this app in it.
    #expect(order == ["prompt", "settings"])
}
