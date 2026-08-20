// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Ambit",
    platforms: [.macOS("26.0")],
    targets: [
        // Pure logic: scanning, status derivation, safe config mutation. No AppKit/SwiftUI.
        .target(name: "AmbitCore"),
        .executableTarget(name: "Ambit", dependencies: ["AmbitCore"]),
        .testTarget(name: "AmbitCoreTests", dependencies: ["AmbitCore"]),
    ]
)
