// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Chop",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Chop", targets: ["Chop"])
  ],
  targets: [
    .executableTarget(name: "Chop")
  ]
)
