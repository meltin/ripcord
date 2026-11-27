// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Ripcord",
  platforms: [.macOS(.v26)],
  dependencies: [
    // Updates in the app; scripts/build-app.sh embeds its framework in Contents/Frameworks.
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
  ],
  targets: [
    .target(name: "RipcordCore"),
    // What the `ripcord` command and the app share: Foundation only, so the command starts fast.
    .target(name: "RipcordControl"),
    .executableTarget(name: "ripcord-cli", dependencies: ["RipcordControl"]),
    .executableTarget(
      name: "Ripcord",
      dependencies: [
        "RipcordCore", "RipcordControl", .product(name: "Sparkle", package: "Sparkle"),
      ],
      // Where the embedded Sparkle.framework is found at run time.
      linkerSettings: [
        .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
      ]
    ),
    .testTarget(name: "RipcordCoreTests", dependencies: ["RipcordCore", "RipcordControl"]),
  ]
)
