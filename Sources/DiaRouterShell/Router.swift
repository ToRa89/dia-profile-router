// Sources/DiaRouterShell/Router.swift
import AppKit
import DiaRouterCore

/// Binds config, profiles, the chooser, and the DiaController together.
@MainActor
public final class Router {
    private let controller: DiaController
    private let chooser: any ProfileChooser
    private let configPath: URL
    private let localStatePath: URL

    public init(
        runner: any AppleScriptRunning = NSAppleScriptRunner(),
        chooser: any ProfileChooser,
        configPath: URL = ConfigStore.defaultPath(),
        localStatePath: URL = ProfileStore.defaultLocalStatePath()
    ) {
        self.controller = DiaController(runner: runner)
        self.chooser = chooser
        self.configPath = configPath
        self.localStatePath = localStatePath
    }

    public func route(_ url: URL) async {
        // Unwrap Outlook SafeLinks, Teams file links, and HTTP redirect services
        // before rule matching so rules fire on the real destination host.
        let resolvedURL = await URLResolver.resolve(url)

        let config = loadConfig()
        let profiles = (try? ProfileStore.loadProfiles(localStatePath: localStatePath)) ?? []
        let engine = RuleEngine(config: config)

        switch engine.decide(for: resolvedURL) {
        case .matched(let dir):
            RoutingLog.logger.info("route \(url.absoluteString, privacy: .public) -> \(dir, privacy: .public) [rule]")
            place(resolvedURL, profileDirectory: dir, engine: engine, profiles: profiles)

        case .needsChoice(let host):
            RoutingLog.logger.info("route \(url.absoluteString, privacy: .public) -> needsChoice host=\(host, privacy: .public)")
            guard let result = await chooser.choose(
                url: resolvedURL, profiles: profiles, defaultDirectory: config.defaultProfileDirectory) else {
                RoutingLog.logger.info("chooser cancelled -> default \(config.defaultProfileDirectory, privacy: .public)")
                place(resolvedURL, profileDirectory: config.defaultProfileDirectory, engine: engine, profiles: profiles)
                return
            }
            if let pattern = result.rememberPattern, !pattern.isEmpty {
                rememberRule(pattern: pattern, profileDirectory: result.profileDirectory)
            }
            RoutingLog.logger.info("chooser -> \(result.profileDirectory, privacy: .public) remember=\(result.rememberPattern ?? "-", privacy: .public)")
            place(resolvedURL, profileDirectory: result.profileDirectory, engine: engine, profiles: profiles)
        }
    }

    private func loadConfig() -> RouterConfig {
        (try? ConfigStore.loadOrDefault(from: configPath, defaultProfileDirectory: "Default"))
            ?? RouterConfig(rules: [], defaultProfileDirectory: "Default")
    }

    /// Append/update a `.host` rule, reading config FRESH right before writing — avoids lost
    /// updates when several needsChoice links resolve one after another.
    private func rememberRule(pattern: String, profileDirectory: String) {
        let updated = RuleSuggestion.appended(
            Rule(matchType: .host, pattern: pattern, profileDirectory: profileDirectory),
            to: loadConfig())
        do { try ConfigStore.save(updated, to: configPath) }
        catch { RoutingLog.logger.error("rule save failed: \(String(describing: error), privacy: .public)") }
    }

    private func place(_ url: URL, profileDirectory: String, engine: RuleEngine, profiles: [Profile]) {
        // A window belongs to the target only if its active tab EXPLICITLY matches a rule for it
        // (matchedRule, not the default fallback — so default routing never hijacks a window).
        let belongs: (URL) -> Bool = { engine.matchedRule(for: $0)?.profileDirectory == profileDirectory }
        do {
            try controller.open(url: url, profileDirectory: profileDirectory,
                                profiles: profiles, belongsToTargetProfile: belongs)
        } catch {
            RoutingLog.logger.error("placement failed, NSWorkspace fallback: \(String(describing: error), privacy: .public)")
            openInDiaDirectly(url)
        }
    }

    private func openInDiaDirectly(_ url: URL) {
        guard let dia = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "company.thebrowser.dia") else {
            NSWorkspace.shared.open(url); return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: dia, configuration: cfg)
    }
}
