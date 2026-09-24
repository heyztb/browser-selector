// swift-tools-version: 6.0
// Copyright (c) 2026 Zach Blake
// SPDX-License-Identifier: GPL-3.0-or-later

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
