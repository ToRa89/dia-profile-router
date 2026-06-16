// Sources/DiaRouterShell/DiaMenu.swift
import Foundation

public enum DiaMenu {
    /// Given a profile display name and the list of menu-item names found under File→New Window,
    /// return the exact menu-item name to click (handling truncation like "New Hausautomatisier… Window").
    public static func newWindowMenuItem(forProfileName name: String, among items: [String]) -> String? {
        let target = name.trimmingCharacters(in: .whitespaces)
        for item in items {
            guard item.hasPrefix("New "), item.hasSuffix(" Window") else { continue }
            var core = String(item.dropFirst(4).dropLast(7))   // strip "New " and " Window"
            // strip trailing ellipsis / "..." used for truncated names
            while core.hasSuffix("…") || core.hasSuffix(".") || core.hasSuffix(" ") { core.removeLast() }
            core = core.trimmingCharacters(in: .whitespaces)
            if core.isEmpty { continue }
            if target.caseInsensitiveCompare(core) == .orderedSame { return item }      // exact
            if target.lowercased().hasPrefix(core.lowercased()) { return item }          // truncated prefix
        }
        return nil
    }
}
