// Sources/DiaRouterShell/AppleScriptRunning.swift
import Foundation
import AppKit

public protocol AppleScriptRunning: Sendable {
    /// Führt ein AppleScript aus und liefert das String-Ergebnis (oder wirft bei Fehler).
    @discardableResult
    func run(_ source: String) throws -> String
}

public struct AppleScriptError: Error, LocalizedError {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct NSAppleScriptRunner: AppleScriptRunning {
    public init() {}
    @discardableResult
    public func run(_ source: String) throws -> String {
        var errorDict: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw AppleScriptError(message: "Konnte AppleScript nicht erstellen")
        }
        let result = script.executeAndReturnError(&errorDict)
        if let error = errorDict {
            throw AppleScriptError(message: "\(error[NSAppleScript.errorMessage] ?? "unbekannt")")
        }
        return result.stringValue ?? ""
    }
}
