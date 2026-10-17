// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Hannyeong",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "HannyeongCore", targets: ["HannyeongCore"]),
        .executable(name: "hannyeong-eval", targets: ["HannyeongEval"]),
        .executable(name: "Hannyeong", targets: ["Hannyeong"]),
    ],
    targets: [
        .systemLibrary(name: "CLibHangul", pkgConfig: "libhangul"),
        .target(name: "HannyeongCore", dependencies: ["CLibHangul"]),
        .executableTarget(name: "HannyeongEval", dependencies: ["HannyeongCore"]),
        .executableTarget(name: "Hannyeong", dependencies: ["HannyeongCore"], linkerSettings: [
            .linkedFramework("AppKit"), .linkedFramework("InputMethodKit"),
            .linkedFramework("Carbon"), .linkedFramework("SwiftUI")
        ]),
        .testTarget(name: "HannyeongCoreTests", dependencies: ["HannyeongCore"]),
    ]
)
