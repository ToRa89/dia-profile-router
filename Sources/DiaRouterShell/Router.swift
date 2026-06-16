// Sources/DiaRouterShell/Router.swift
import AppKit
import DiaRouterCore

/// Bindet Config, Profile und DiaController zusammen.
@MainActor
public final class Router {
    private let controller: DiaController

    public init(runner: any AppleScriptRunning = NSAppleScriptRunner()) {
        self.controller = DiaController(runner: runner)
    }

    public func route(_ url: URL) {
        do {
            let config = try ConfigStore.loadOrDefault(
                from: ConfigStore.defaultPath(), defaultProfileDirectory: "Default")
            let profiles = (try? ProfileStore.loadProfiles(
                localStatePath: ProfileStore.defaultLocalStatePath())) ?? []

            let engine = RuleEngine(config: config)
            let target = engine.profileDirectory(for: url)

            // A window belongs to the target profile if its active tab EXPLICITLY matches a
            // rule for that profile (matchedRule, not the default fallback — so default-profile
            // routing never hijacks an arbitrary open window).
            let belongs: (URL) -> Bool = { engine.matchedRule(for: $0)?.profileDirectory == target }

            try controller.open(
                url: url, profileDirectory: target, profiles: profiles,
                belongsToTargetProfile: belongs)
        } catch {
            // Degradation: Link nie verlieren -> an Dia (Default-Profil) durchreichen
            NSLog("Routing fehlgeschlagen, Fallback NSWorkspace: \(error)")
            openInDiaDirectly(url)
        }
    }

    private func openInDiaDirectly(_ url: URL) {
        guard let dia = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "company.thebrowser.dia") else {
            NSWorkspace.shared.open(url); return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: dia, configuration: cfg)
    }
}
