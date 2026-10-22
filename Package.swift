// swift-tools-version: 6.0
import PackageDescription

// Plinth builds with the Command Line Tools alone (`xcode-select --install`).
// No Xcode project and no Apple account are needed. `make` assembles the .app bundle.
let package = Package(
    name: "Plinth",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Plinth", targets: ["Plinth"])
    ],
    targets: [
        .target(
            name: "PlinthKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Plinth",
            dependencies: ["PlinthKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PlinthKitTests",
            dependencies: ["PlinthKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
