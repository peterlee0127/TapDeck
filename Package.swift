// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TapDeck",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TapDeck", targets: ["TapDeck"])
    ],
    targets: [
        .executableTarget(
            name: "TapDeck",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .testTarget(
            name: "TapDeckTests",
            dependencies: ["TapDeck"]
        )
    ]
)
