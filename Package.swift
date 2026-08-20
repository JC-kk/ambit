// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AgentCapabilityManager",
    platforms: [.macOS("26.0")],
    targets: [
        // Pure logic: scanning, status derivation, safe config mutation. No AppKit/SwiftUI.
        .target(name: "ACMCore"),
        .executableTarget(name: "AgentCapabilityManager", dependencies: ["ACMCore"]),
        .testTarget(name: "ACMCoreTests", dependencies: ["ACMCore"]),
    ]
)
