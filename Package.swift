// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "BrowserSelector",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "BrowserSelector", targets: ["BrowserSelector"])
  ],
  targets: [
    .executableTarget(
      name: "BrowserSelector",
      path: "Sources/BrowserSelector"
    ),
    .testTarget(
      name: "BrowserSelectorTests",
      dependencies: ["BrowserSelector"],
      path: "Tests/BrowserSelectorTests"
    ),
  ]
)
