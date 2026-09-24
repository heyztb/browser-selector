// Copyright (c) 2026 Zach Blake
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest

@testable import BrowserSelector

final class BrowserDiscoveryTests: XCTestCase {
  func testBuilderExcludesSelfDeduplicatesBundlesAndReplacesFirefoxWithProfiles() {
    let applications = [
      application("io.github.heyztb.BrowserSelector", name: "Browser Selector"),
      application("com.apple.Safari", name: "Safari", path: "/Applications/Safari.app"),
      application("com.apple.Safari", name: "Safari Copy", path: "/Other/Safari.app"),
      application("org.mozilla.firefox", name: "Firefox"),
    ]
    let profiles = [
      FirefoxProfile(
        name: "Personal",
        path: URL(fileURLWithPath: "/Profiles/personal"),
        isRegistered: true,
        compatibility: FirefoxCompatibility(
          lastPlatformDirectory: "/Applications/Firefox.app/Contents/Resources")
      ),
      FirefoxProfile(
        name: "Work",
        path: URL(fileURLWithPath: "/Profiles/work"),
        isRegistered: false,
        compatibility: FirefoxCompatibility(
          lastPlatformDirectory: "/Applications/Firefox.app/Contents/Resources")
      ),
    ]

    let targets = BrowserTargetBuilder.build(
      applications: applications,
      currentBundleIdentifier: "io.github.heyztb.BrowserSelector",
      firefoxProfiles: profiles
    ).targets

    XCTAssertEqual(targets.map(\.displayName), ["Safari", "Personal", "Work"])
    XCTAssertEqual(targets.filter { $0.bundleIdentifier == "com.apple.Safari" }.count, 1)
    XCTAssertFalse(targets.contains { $0.bundleIdentifier == "io.github.heyztb.BrowserSelector" })
    XCTAssertTrue(targets.suffix(2).allSatisfy { $0.profilePath != nil })
  }

  func testBuilderKeepsGenericFirefoxWhenNoProfilesExist() {
    let targets = BrowserTargetBuilder.build(
      applications: [application("org.mozilla.firefox", name: "Firefox")],
      currentBundleIdentifier: "self",
      firefoxProfiles: []
    ).targets
    XCTAssertEqual(targets.count, 1)
    XCTAssertEqual(targets[0].kind, .application)
  }

  func testEditionsOwnTheirProfilesAndUnmatchedProfilesAreSkipped() {
    let regular = application("org.mozilla.firefox", name: "Firefox")
    let developer = application(
      "org.mozilla.firefoxdeveloperedition", name: "Firefox Developer Edition")
    let profiles = [regular, regular, developer].enumerated().map { index, app in
      FirefoxProfile(
        name: "Profile \(index)", path: URL(fileURLWithPath: "/Profiles/\(index)"),
        isRegistered: index != 1,
        compatibility: FirefoxCompatibility(
          lastPlatformDirectory: app.appURL.path + "/Contents/Resources"))
    }
    let result = BrowserTargetBuilder.build(
      applications: [regular, developer],
      currentBundleIdentifier: "self", firefoxProfiles: profiles)
    XCTAssertEqual(result.targets.count, 3)
    XCTAssertEqual(
      result.targets.map(\.appURL), [regular.appURL, regular.appURL, developer.appURL])
    XCTAssertTrue(result.targets.allSatisfy { $0.profilePath != nil })
    XCTAssertTrue(result.warnings.isEmpty)

    let developerOnly = BrowserTargetBuilder.build(
      applications: [developer],
      currentBundleIdentifier: "self", firefoxProfiles: profiles)
    XCTAssertEqual(developerOnly.targets.count, 1)
    XCTAssertEqual(developerOnly.targets.first?.profilePath, profiles[2].path)
    XCTAssertEqual(developerOnly.warnings.count, 2)

    let unknown = FirefoxProfile(
      name: "Unknown", path: URL(fileURLWithPath: "/Profiles/unknown"),
      isRegistered: true)
    let fallback = BrowserTargetBuilder.build(
      applications: [regular, developer],
      currentBundleIdentifier: "self", firefoxProfiles: [unknown])
    XCTAssertEqual(fallback.targets.map(\.kind), [.application, .application])
    XCTAssertEqual(fallback.warnings.count, 1)
  }

  func testMultipleDeveloperProfilesUseMatchedCopyOfApplication() {
    let first = application(
      "org.mozilla.firefoxdeveloperedition", name: "Dev", path: "/Other/Dev.app")
    let matched = application(
      "org.mozilla.firefoxdeveloperedition", name: "Dev", path: "/Applications/Dev.app")
    let regular = application("org.mozilla.firefox", name: "Firefox")
    let profiles = (0..<2).map { index in
      FirefoxProfile(
        name: "Dev \(index)", path: URL(fileURLWithPath: "/Profiles/dev\(index)"),
        isRegistered: true,
        compatibility: FirefoxCompatibility(
          lastPlatformDirectory: matched.appURL.path + "/Contents/Resources"))
    }
    let result = BrowserTargetBuilder.build(
      applications: [first, matched, regular],
      currentBundleIdentifier: "self", firefoxProfiles: profiles)
    XCTAssertEqual(result.targets.count, 3)
    XCTAssertEqual(result.targets.prefix(2).map(\.appURL), [matched.appURL, matched.appURL])
    XCTAssertEqual(result.targets.last?.kind, .application)
    XCTAssertTrue(result.warnings.isEmpty)
    let appPreferences = [
      BrowserTarget.applicationID(bundleIdentifier: matched.bundleIdentifier):
        TargetPreferences(customName: "App name", isVisible: false, order: 0)
    ]
    let reconciled = TargetReconciler.reconcile(
      discovered: result.targets, preferences: appPreferences)
    XCTAssertTrue(reconciled.allSatisfy(\.isVisible))
    XCTAssertTrue(reconciled.allSatisfy { $0.customName == nil })
  }

  func testCompatibilityRejectsConflictsMalformedAndStalePaths() {
    let app = application("org.mozilla.firefox", name: "Firefox")
    let resources = app.appURL.path + "/Contents/Resources"
    XCTAssertTrue(
      FirefoxCompatibility.parse("[Compatibility]\nLastAppDir=\(resources)/browser").matches(app))
    XCTAssertTrue(
      FirefoxCompatibility.parse(
        "[Compatibility]\nLastPlatformDir=\(resources)\nLastAppDir=\(resources)/browser"
      ).matches(app))
    for contents in [
      "", "[Other]\nLastPlatformDir=\(resources)",
      "[Compatibility]\nLastPlatformDir=relative/path",
      "[Compatibility]\nLastPlatformDir=",
      "[Compatibility]\nLastPlatformDir=/Old/Firefox.app/Contents/Resources",
      "[Compatibility]\nLastPlatformDir=\(resources)\nLastAppDir=/Other/browser",
      "[Compatibility]\nLastPlatformDir=bad\nLastAppDir=\(resources)/browser",
    ] {
      XCTAssertFalse(FirefoxCompatibility.parse(contents).matches(app), contents)
    }
  }

  func testCompatibilityResolvesSymlinksAndSpaces() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let app = root.appendingPathComponent("Firefox Developer Edition.app")
    try FileManager.default.createDirectory(
      at: app.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
    let alias = root.appendingPathComponent("Alias.app")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: app)
    let record = application("org.mozilla.firefoxdeveloperedition", name: "Dev", path: app.path)
    XCTAssertTrue(
      FirefoxCompatibility(lastPlatformDirectory: alias.path + "/Contents/Resources").matches(
        record))
  }

  private func application(
    _ bundleIdentifier: String,
    name: String,
    path: String? = nil
  ) -> BrowserApplicationRecord {
    BrowserApplicationRecord(
      bundleIdentifier: bundleIdentifier,
      appURL: URL(fileURLWithPath: path ?? "/Applications/\(name).app"),
      displayName: name
    )
  }
}
