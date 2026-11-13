// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SSTL",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SSTL", targets: ["SSTL"])
    ],
    targets: [
        .executableTarget(name: "SSTL", path: "Sources/SSTL")
    ]
)
