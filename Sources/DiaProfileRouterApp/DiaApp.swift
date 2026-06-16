// Sources/DiaProfileRouterApp/DiaApp.swift
import SwiftUI
import DiaRouterShell

@main
struct DiaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        MenuBarExtra("Dia Router", systemImage: "arrow.triangle.branch") {
            SettingsView()
        }
        .menuBarExtraStyle(.window)
    }
}
