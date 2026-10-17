// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "JevKoreanIMEExperiment",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "JevIMECore", targets: ["JevIMECore"]),
        .executable(name: "jev-ime-eval", targets: ["JevIMEEval"]),
        .executable(name: "JevType", targets: ["JevType"]),
    ],
    targets: [
        .systemLibrary(name: "CLibHangul", pkgConfig: "libhangul"),
        .target(name: "JevIMECore", dependencies: ["CLibHangul"]),
        .executableTarget(name: "JevIMEEval", dependencies: ["JevIMECore"]),
        .executableTarget(name: "JevType", dependencies: ["JevIMECore"], linkerSettings: [
            .linkedFramework("AppKit"), .linkedFramework("InputMethodKit"),
            .linkedFramework("Carbon"), .linkedFramework("SwiftUI")
        ]),
        .testTarget(name: "JevIMECoreTests", dependencies: ["JevIMECore"]),
    ]
)
