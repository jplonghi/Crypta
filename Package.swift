// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CryptaDesktop",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CryptaDesktop", targets: ["CryptaDesktop"])],
    dependencies: [.package(path: "Packages/CryptaCore")],
    targets: [
        .target(name: "CryptaDesktop", dependencies: ["CryptaCore"], path: "CryptaApp", exclude: ["App", "Resources"]),
        .testTarget(name: "CryptaDesktopTests", dependencies: ["CryptaDesktop", "CryptaCore"], path: "CryptaAppTests")
    ]
)
