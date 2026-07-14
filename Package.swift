// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DamSet",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(name: "DamSetCore", targets: ["DamSetCore"]),
        .library(name: "DamSetLiveActivity", targets: ["DamSetLiveActivity"]),
        .executable(name: "DamSetAppShell", targets: ["DamSetAppShell"]),
        .executable(name: "DamSetCoreSmoke", targets: ["DamSetCoreSmoke"])
    ],
    targets: [
        .target(name: "DamSetCore"),
        .target(
            name: "DamSetLiveActivity",
            dependencies: ["DamSetCore"],
            path: "DamSetLiveActivity",
            exclude: ["Info.plist", "DamSetLiveActivity.entitlements"]
        ),
        .executableTarget(
            name: "DamSetAppShell",
            dependencies: ["DamSetCore"],
            path: "DamSetApp",
            exclude: ["Info.plist", "DamSet.entitlements", "Assets.xcassets"]
        ),
        .executableTarget(name: "DamSetCoreSmoke", dependencies: ["DamSetCore"]),
        .testTarget(
            name: "DamSetCoreTests",
            dependencies: ["DamSetCore"],
            path: "XcodeTests/DamSetCoreTests"
        )
    ]
)
