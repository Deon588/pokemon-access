// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PokemonAccess",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "PokemonAccessCore",
            path: "Sources/PokemonAccessCore"
        ),
        .executableTarget(
            name: "PokemonAccess",
            dependencies: ["PokemonAccessCore"],
            path: "Sources/PokemonAccess"
        ),
        .testTarget(
            name: "PokemonAccessCoreTests",
            dependencies: ["PokemonAccessCore"],
            path: "Tests/PokemonAccessCoreTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
