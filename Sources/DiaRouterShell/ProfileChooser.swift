// Sources/DiaRouterShell/ProfileChooser.swift
import Foundation
import DiaRouterCore

/// The user's decision from the profile chooser.
public struct ChooserResult: Equatable, Sendable {
    /// Chosen profile directory (e.g. "Profile 9").
    public let profileDirectory: String
    /// Host pattern to remember as a new `.host` rule, or nil to not create a rule.
    public let rememberPattern: String?
    public init(profileDirectory: String, rememberPattern: String?) {
        self.profileDirectory = profileDirectory
        self.rememberPattern = rememberPattern
    }
}

/// Presents a profile chooser to the user. Production shows a window; tests inject a mock.
/// Returns nil when the user cancels.
@MainActor
public protocol ProfileChooser {
    func choose(url: URL, profiles: [Profile], defaultDirectory: String) async -> ChooserResult?
}
