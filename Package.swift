// swift-tools-version: 5.9
import PackageDescription

// The platform-independent logic is testable without AppKit or a Mac.
let package = Package(
    name: "RelayBarCore",
    products: [.library(name: "RelayCore", targets: ["RelayCore"])],
    targets: [
        .target(name: "RelayCore", path: "Sources/Core"),
        .testTarget(name: "RelayCoreTests", dependencies: ["RelayCore"], path: "Tests/RelayCoreTests")
    ]
)
