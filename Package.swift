// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Skillswitch",
    platforms: [.macOS("26.0")],
    targets: [
        // Pure logic: scanning, status derivation, safe config mutation. No AppKit/SwiftUI.
        .target(name: "SkillswitchCore"),
        .executableTarget(name: "Skillswitch", dependencies: ["SkillswitchCore"]),
        .testTarget(name: "SkillswitchCoreTests", dependencies: ["SkillswitchCore"]),
    ]
)
