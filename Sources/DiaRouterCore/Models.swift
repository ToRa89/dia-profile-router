// Sources/DiaRouterCore/Models.swift
import Foundation

public struct Profile: Equatable, Codable, Identifiable, Sendable {
    public let directory: String   // z.B. "Profile 6" oder "Default"
    public let name: String        // Anzeigename, z.B. "Work"
    public var id: String { directory }
    public init(directory: String, name: String) {
        self.directory = directory
        self.name = name
    }
}

public enum MatchType: String, Codable, CaseIterable, Sendable {
    case exact    // voller URL-String (normalisiert)
    case prefix   // host+path beginnt mit Pattern
    case host     // host == Pattern oder Subdomain davon
    case wildcard // * als Platzhalter; ohne "/" gegen host, sonst gegen host+path
}

public struct Rule: Equatable, Codable, Identifiable, Sendable {
    public let id: UUID
    public var matchType: MatchType
    public var pattern: String
    public var profileDirectory: String
    public init(id: UUID = UUID(), matchType: MatchType, pattern: String, profileDirectory: String) {
        self.id = id
        self.matchType = matchType
        self.pattern = pattern
        self.profileDirectory = profileDirectory
    }
}

public struct RouterConfig: Equatable, Codable, Sendable {
    public var rules: [Rule]
    public var defaultProfileDirectory: String
    public init(rules: [Rule], defaultProfileDirectory: String) {
        self.rules = rules
        self.defaultProfileDirectory = defaultProfileDirectory
    }
}
