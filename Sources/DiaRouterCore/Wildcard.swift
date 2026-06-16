// Sources/DiaRouterCore/Wildcard.swift
// Portiert aus Finicky (johnste/finicky), packages/config-api/src/wildcard.ts — MIT License.
import Foundation

public enum Wildcard {
    /// Voller Match: `*` steht für beliebige (auch leere) Zeichenfolge; alles andere literal.
    public static func matches(pattern: String, value: String) -> Bool {
        let regex = "^" + pattern
            .components(separatedBy: "*")
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: ".*") + "$"
        guard let re = try? NSRegularExpression(pattern: regex, options: [.dotMatchesLineSeparators]) else {
            return false
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return re.firstMatch(in: value, options: [], range: range) != nil
    }
}
