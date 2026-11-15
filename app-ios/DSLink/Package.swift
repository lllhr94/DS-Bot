// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DSLink",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "DSLink", targets: ["DSLink"])],
    targets: [
        .target(name: "DSLink"),
        .testTarget(name: "DSLinkTests", dependencies: ["DSLink"]),
    ]
)
