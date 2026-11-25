// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Ripcord",
  platforms: [.macOS(.v26)],
  targets: [
    .target(name: "RipcordCore"),
    .executableTarget(name: "Ripcord", dependencies: ["RipcordCore"]),
    .testTarget(name: "RipcordCoreTests", dependencies: ["RipcordCore"]),
  ]
)
