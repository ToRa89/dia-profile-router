// Sources/DiaProfileRouterApp/DiaApp.swift
import SwiftUI
import DiaRouterShell

@main
struct DiaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        MenuBarExtra {
            SettingsView()
        } label: {
            if let icon = MenuBarIcon.image {
                Image(nsImage: icon)
            } else {
                Image(systemName: "arrow.triangle.branch")   // bundle asset missing
            }
        }
        .menuBarExtraStyle(.window)
    }
}
