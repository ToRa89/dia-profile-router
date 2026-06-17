// Sources/DiaProfileRouterApp/ConfigViewModel.swift
import SwiftUI
import DiaRouterCore
import DiaRouterShell

@MainActor
final class ConfigViewModel: ObservableObject {
    @Published var config: RouterConfig
    @Published var profiles: [Profile] = []
    @Published var isDefaultBrowser = false
    @Published var isAccessibilityGranted = false

    init() {
        let profs = (try? ProfileStore.loadProfiles(localStatePath: ProfileStore.defaultLocalStatePath())) ?? []
        self.profiles = profs
        let def = profs.first?.directory ?? "Default"
        self.config = (try? ConfigStore.loadOrDefault(from: ConfigStore.defaultPath(), defaultProfileDirectory: def))
            ?? RouterConfig(rules: [], defaultProfileDirectory: def)
        self.isDefaultBrowser = DefaultBrowser.isDefault()
        self.isAccessibilityGranted = AccessibilityPermission.isGranted()
    }

    /// Re-reads profiles, config, and default-browser status from disk. Called when the window
    /// appears so externally-made changes show up (the @StateObject persists across popover
    /// open/close, so init() alone would keep showing a stale snapshot).
    func reload() {
        let profs = (try? ProfileStore.loadProfiles(localStatePath: ProfileStore.defaultLocalStatePath())) ?? []
        profiles = profs
        let def = profs.first?.directory ?? "Default"
        config = (try? ConfigStore.loadOrDefault(from: ConfigStore.defaultPath(), defaultProfileDirectory: def))
            ?? RouterConfig(rules: [], defaultProfileDirectory: def)
        isDefaultBrowser = DefaultBrowser.isDefault()
        isAccessibilityGranted = AccessibilityPermission.isGranted()
    }

    func save() {
        try? ConfigStore.save(config, to: ConfigStore.defaultPath())
    }

    func addRule() {
        let def = profiles.first?.directory ?? config.defaultProfileDirectory
        config.rules.append(Rule(matchType: .host, pattern: "", profileDirectory: def))
        save()
    }

    func deleteRule(_ rule: Rule) {
        config.rules.removeAll { $0.id == rule.id }
        save()
    }

    func profileName(_ dir: String) -> String {
        profiles.first { $0.directory == dir }?.name ?? dir
    }

    func setAsDefaultBrowser() {
        DefaultBrowser.setAsDefault()
        isDefaultBrowser = DefaultBrowser.isDefault()
    }

    func openAccessibilitySettings() {
        AccessibilityPermission.openSettings()
    }
}
