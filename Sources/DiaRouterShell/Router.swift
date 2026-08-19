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
        if resolvedURL != url {
            RoutingLog.logger.info("resolve \(url.absoluteString, privacy: .public) -> \(resolvedURL.absoluteString, privacy: .public)")
        }

        let config = loadConfig()
        let profiles = (try? ProfileStore.loadProfiles(localStatePath: localStatePath)) ?? []
        let engine = RuleEngine(config: config)

        switch engine.decide(for: resolvedURL) {
        case .matched(let dir):
            RoutingLog.logger.info("route \(url.absoluteString, privacy: .public) -> \(dir, privacy: .public) [rule]")
            place(resolvedURL, profileDirectory: dir, engine: engine, profiles: profiles,
                  defaultDirectory: config.defaultProfileDirectory)

        case .needsChoice(let host):
            RoutingLog.logger.info("route \(url.absoluteString, privacy: .public) -> needsChoice host=\(host, privacy: .public)")
            guard let result = await chooser.choose(
                url: resolvedURL, profiles: profiles, defaultDirectory: config.defaultProfileDirectory) else {
                RoutingLog.logger.info("chooser cancelled -> default \(config.defaultProfileDirectory, privacy: .public)")
                place(resolvedURL, profileDirectory: config.defaultProfileDirectory, engine: engine,
                      profiles: profiles, defaultDirectory: config.defaultProfileDirectory)
                return
            }
            if let pattern = result.rememberPattern, !pattern.isEmpty {
                rememberRule(pattern: pattern, profileDirectory: result.profileDirectory)
            }
            RoutingLog.logger.info("chooser -> \(result.profileDirectory, privacy: .public) remember=\(result.rememberPattern ?? "-", privacy: .public)")
            place(resolvedURL, profileDirectory: result.profileDirectory, engine: engine,
                  profiles: profiles, defaultDirectory: config.defaultProfileDirectory)
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

    private func place(_ url: URL, profileDirectory: String, engine: RuleEngine, profiles: [Profile],
                       defaultDirectory: String) {
        let target = resolveExistingProfile(profileDirectory, profiles: profiles, defaultDirectory: defaultDirectory)
        // A window belongs to the target only if its active tab EXPLICITLY matches a rule for it
        // (matchedRule, not the default fallback — so default routing never hijacks a window).
        let belongs: (URL) -> Bool = { engine.matchedRule(for: $0)?.profileDirectory == target }
        do {
            try controller.open(url: url, profileDirectory: target,
                                profiles: profiles, belongsToTargetProfile: belongs)
        } catch {
            RoutingLog.logger.error("placement failed, NSWorkspace fallback: \(String(describing: error), privacy: .public)")
            openInDiaDirectly(url)
        }
    }

    /// Rules outlive the profiles they point at: deleting a profile in Dia leaves its directory
    /// behind in the config. Route such links to the default profile instead of letting them land
    /// in whichever profile happens to be in front. Profiles are re-read on every link, so
    /// additions and removals in Dia are picked up without restarting the app.
    private func resolveExistingProfile(_ directory: String, profiles: [Profile],
                                       defaultDirectory: String) -> String {
        // Empty list == Local State unreadable; that says nothing about the profile, so keep it.
        guard !profiles.isEmpty, !profiles.contains(where: { $0.directory == directory }) else {
            return directory
        }
        guard profiles.contains(where: { $0.directory == defaultDirectory }) else {
            RoutingLog.logger.info(
                "profile \(directory, privacy: .public) gone, default \(defaultDirectory, privacy: .public) gone too -> front window")
            return directory
        }
        RoutingLog.logger.info(
            "profile \(directory, privacy: .public) no longer exists in Dia -> default \(defaultDirectory, privacy: .public)")
        return defaultDirectory
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
