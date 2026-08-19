// Sources/DiaRouterShell/DiaProfileNames.swift
import Foundation

/// Matches a profile display name (from Dia's `Local State`) against the profile names Dia
/// reports over AppleScript.
///
/// Deliberately name-based only: never by position or prefix. Dia's profile order shifts as
/// soon as a profile is added, removed, or reordered, so anything positional silently starts
/// addressing the neighbouring profile.
public enum DiaProfileNames {
    /// The exact spelling Dia uses for `name`, or nil if Dia does not offer that profile.
    /// Prefers a byte-exact hit, then falls back to a case-, whitespace- and Unicode-form
    /// insensitive comparison (`Local State` JSON and AppleScript can disagree on NFC/NFD).
    public static func resolve(_ name: String, among candidates: [String]) -> String? {
        if let exact = candidates.first(where: { $0 == name }) { return exact }
        return candidates.first { isSameProfile($0, name) }
    }

    /// True if both strings name the same profile, ignoring case, surrounding whitespace,
    /// and Unicode normalisation form.
    public static func isSameProfile(_ lhs: String, _ rhs: String) -> Bool {
        normalized(lhs) == normalized(rhs) && !normalized(lhs).isEmpty
    }

    private static func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }
}
