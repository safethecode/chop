// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Chop",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Chop", targets: ["Chop"])
  ],
  targets: [
    .binaryTarget(name: "GhosttyKit", path: "Dependencies/GhosttyKit.xcframework"),
    .executableTarget(
      name: "Chop",
      dependencies: ["GhosttyKit"],
      linkerSettings: [
        .linkedLibrary("c++"),
        .linkedFramework("Carbon"),
        .linkedFramework("CoreText"),
        .linkedFramework("CoreVideo"),
        .linkedFramework("Metal"),
        .linkedFramework("QuartzCore"),
        .linkedFramework("IOSurface"),
      ]
    ),
    .testTarget(name: "ChopTests", dependencies: ["Chop"]),
  ]
)
