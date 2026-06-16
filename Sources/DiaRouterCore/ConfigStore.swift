// Sources/DiaRouterCore/ConfigStore.swift
import Foundation

public enum ConfigStore {
    public static func defaultPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/dia-router/config.json")
    }

    public static func save(_ config: RouterConfig, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> RouterConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RouterConfig.self, from: data)
    }

    public static func loadOrDefault(from url: URL, defaultProfileDirectory: String) throws -> RouterConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return RouterConfig(rules: [], defaultProfileDirectory: defaultProfileDirectory)
        }
        return try load(from: url)
    }
}
