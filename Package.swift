// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiaProfileRouter",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic library (Tasks 0–7)
        .target(name: "DiaRouterCore"),
        .testTarget(
            name: "DiaRouterCoreTests",
            dependencies: ["DiaRouterCore"],
            resources: [.copy("Fixtures")]
        ),

        // App-shell library: injectable abstractions + routing logic (Tasks 8–11)
        .target(
            name: "DiaRouterShell",
            dependencies: ["DiaRouterCore"]
        ),
        .testTarget(
            name: "DiaRouterShellTests",
            dependencies: ["DiaRouterShell"]
        ),

        // Thin executable: @main + AppDelegate only (Task 12)
        .executableTarget(
            name: "DiaProfileRouterApp",
            dependencies: ["DiaRouterShell"]
        ),
    ]
)
