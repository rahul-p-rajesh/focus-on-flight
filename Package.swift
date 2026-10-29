// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Contrail",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "Contrail", targets: ["Contrail"]),
    ],
    targets: [
        .target(name: "ContrailCore"),
        .executableTarget(
            name: "Contrail",
            dependencies: ["ContrailCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "ContrailCoreTests", dependencies: ["ContrailCore"]),
    ]
)
