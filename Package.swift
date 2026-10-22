// swift-tools-version: 6.0
import PackageDescription

// DockFlip builds with the Command Line Tools alone (`xcode-select --install`).
// No Xcode project and no Apple account are needed. `make` assembles the .app bundle.
let package = Package(
    name: "DockFlip",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "DockFlip", targets: ["DockFlip"])
    ],
    targets: [
        .target(
            name: "DockFlipKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "DockFlip",
            dependencies: ["DockFlipKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DockFlipKitTests",
            dependencies: ["DockFlipKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
