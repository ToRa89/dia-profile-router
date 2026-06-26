// Sources/DiaRouterShell/RoutingLog.swift
import Foundation
import os

/// Central logger for routing decisions. Query with:
///   log show --predicate 'subsystem == "com.tora89.dia-profile-router"' --info
public enum RoutingLog {
    public static let logger = Logger(subsystem: "com.tora89.dia-profile-router", category: "routing")
}
