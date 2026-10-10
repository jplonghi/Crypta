// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CryptaCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CryptaCore", targets: ["CryptaCore"])],
    dependencies: [.package(url: "https://github.com/jedisct1/swift-sodium.git", exact: "0.11.0")],
    targets: [
        .target(name: "CryptaCore", dependencies: [.product(name: "Clibsodium", package: "swift-sodium")]),
        .executableTarget(name: "CryptaTestDriver", dependencies: ["CryptaCore"], path: "Tests/Support/CryptaTestDriver"),
        .testTarget(name: "CryptaCoreTests", dependencies: ["CryptaCore"], resources: [.copy("Fixtures")])
    ]
)
