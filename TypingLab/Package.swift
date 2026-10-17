// swift-tools-version: 5.10
import PackageDescription

let package = Package(name: "TypingLab", platforms: [.macOS(.v13)], products: [
    .executable(name: "TypingLab", targets: ["TypingLab"])
], targets: [
    .target(name: "TypingLabCore"),
    .executableTarget(name: "TypingLab", dependencies: ["TypingLabCore"],
                      linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("Carbon")]),
    .testTarget(name: "TypingLabCoreTests", dependencies: ["TypingLabCore"])
])
