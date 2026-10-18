// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lattice",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LayoutModel", targets: ["LayoutModel"]),
        .library(name: "LayoutEngine", targets: ["LayoutEngine"]),
        .library(name: "Platform", targets: ["Platform"]),
        .library(name: "PlatformMac", targets: ["PlatformMac"]),
        .library(name: "Config", targets: ["Config"]),
        .library(name: "AppCore", targets: ["AppCore"]),
        .executable(name: "lattice-cli", targets: ["LatticeCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/dduan/TOMLDecoder.git", exact: "0.3.0"),
    ],
    targets: [
        .target(
            name: "LayoutModel",
            path: "Packages/LayoutModel/Sources"
        ),
        .testTarget(
            name: "LayoutModelTests",
            dependencies: ["LayoutModel"],
            path: "Packages/LayoutModel/Tests"
        ),
        .target(
            name: "LayoutEngine",
            dependencies: ["LayoutModel"],
            path: "Packages/LayoutEngine/Sources"
        ),
        .testTarget(
            name: "LayoutEngineTests",
            dependencies: ["LayoutEngine", "LayoutModel"],
            path: "Packages/LayoutEngine/Tests"
        ),
        .target(
            name: "Platform",
            path: "Packages/Platform/Sources"
        ),
        .testTarget(
            name: "PlatformTests",
            dependencies: ["Platform"],
            path: "Packages/Platform/Tests",
            resources: [
                .copy("Fixtures")
            ]
        ),
        .target(
            name: "PlatformMac",
            dependencies: ["Platform", "LayoutModel"],
            path: "Packages/PlatformMac/Sources"
        ),
        .testTarget(
            name: "PlatformMacTests",
            dependencies: ["PlatformMac", "Platform"],
            path: "Packages/PlatformMac/Tests"
        ),
        .target(
            name: "Config",
            dependencies: [
                "LayoutModel",
                .product(name: "TOMLDecoder", package: "TOMLDecoder"),
            ],
            path: "Packages/Config/Sources",
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "ConfigTests",
            dependencies: ["Config", "LayoutModel"],
            path: "Packages/Config/Tests"
        ),
        .target(
            name: "AppCore",
            dependencies: [
                "LayoutModel",
                "LayoutEngine",
                "Platform",
                "Config",
            ],
            path: "Packages/AppCore/Sources"
        ),
        .testTarget(
            name: "AppCoreTests",
            dependencies: ["AppCore", "LayoutModel", "LayoutEngine", "Platform", "Config"],
            path: "Packages/AppCore/Tests"
        ),
        .executableTarget(
            name: "LatticeCLI",
            dependencies: ["Config", "LayoutModel"],
            path: "Packages/LatticeCLI/Sources"
        ),
    ]
)
