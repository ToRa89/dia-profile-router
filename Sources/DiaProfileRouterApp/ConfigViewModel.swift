// Sources/DiaProfileRouterApp/ConfigViewModel.swift
import SwiftUI
import DiaRouterCore
import DiaRouterShell

@MainActor
final class ConfigViewModel: ObservableObject {
    @Published var config: RouterConfig
    @Published var profiles: [Profile] = []
    @Published var isDefaultBrowser = false
    /// Separate status: setting the default browser only rebinds http/https, not the
    /// `public.html` file-type binding used when a local .html file is opened.
    @Published var isDefaultForLocalHTML = false
    @Published var isAccessibilityGranted = false

    /// ~1 minute of one-second checks — long enough to walk through System Settings, short enough
    /// to stop on its own if the user abandons the flow.
    private static let accessibilityPollAttempts = 60
    private var accessibilityPoll: Task<Void, Never>?

    init() {
        let profs = (try? ProfileStore.loadProfiles(localStatePath: ProfileStore.defaultLocalStatePath())) ?? []
        self.profiles = profs
        let def = profs.first?.directory ?? "Default"
        self.config = (try? ConfigStore.loadOrDefault(from: ConfigStore.defaultPath(), defaultProfileDirectory: def))
            ?? RouterConfig(rules: [], defaultProfileDirectory: def)
        self.isDefaultBrowser = DefaultBrowser.isDefault()
        self.isDefaultForLocalHTML = DefaultBrowser.isDefaultForLocalHTML()
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
        isDefaultForLocalHTML = DefaultBrowser.isDefaultForLocalHTML()
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
        isDefaultForLocalHTML = DefaultBrowser.isDefaultForLocalHTML()
    }

    func setAsDefaultForLocalHTML() {
        DefaultBrowser.setAsDefaultForLocalHTML()
        isDefaultForLocalHTML = DefaultBrowser.isDefaultForLocalHTML()
    }

    /// Triggers the system Accessibility prompt, which registers the app in
    /// System Settings → Privacy & Security → Accessibility, and opens that pane. Granting itself
    /// stays the user's (password-protected) action in System Settings.
    func requestAccessibility() {
        if AccessibilityPermission.request() {
            RoutingLog.logger.info("accessibility request -> already granted")
            isAccessibilityGranted = true
            return
        }
        RoutingLog.logger.info("accessibility request -> prompted, app registered in the list")
        pollAccessibilityStatus()
    }

    /// The switch is flipped outside this process, so poll briefly instead of leaving a stale
    /// "not allowed" badge until the user reopens this window.
    private func pollAccessibilityStatus() {
        accessibilityPoll?.cancel()
        accessibilityPoll = Task { [weak self] in
            for _ in 0..<Self.accessibilityPollAttempts {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                if AccessibilityPermission.isGranted() {
                    self.isAccessibilityGranted = true
                    return
                }
            }
        }
    }
}
