// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Daylapse",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Daylapse", targets: ["Daylapse"])
    ],
    targets: [
        .executableTarget(name: "Daylapse", path: "Sources/Daylapse")
    ]
)
