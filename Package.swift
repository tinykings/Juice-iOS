// swift-tools-version:5.9
// The app's plain-Swift core (Juice/Core), built and tested on its own with
// `swift test`, including on Linux. The app itself is built from Juice.xcodeproj.
import PackageDescription

let package = Package(
    name: "JuiceCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    targets: [
        .target(name: "JuiceCore", path: "Juice/Core"),
        .testTarget(name: "JuiceCoreTests", dependencies: ["JuiceCore"], path: "Tests/JuiceCoreTests"),
    ]
)
