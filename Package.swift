// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "macaskpass",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "macaskpass",
            path: "Sources/macaskpass",
            linkerSettings: [
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("Security"),
                .linkedFramework("OpenDirectory"),
            ]
        )
    ]
)
