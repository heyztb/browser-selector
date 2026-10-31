// Copyright (c) 2026 Zach Blake
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest

@testable import BrowserSelector

final class ChromiumProfilesTests: XCTestCase {
  private let brave = ChromiumBrowser.browser(bundleIdentifier: "com.brave.Browser")!

  func testParserReadsInfoCacheNamesAndRejectsUnsafeDirectories() throws {
    let root = URL(fileURLWithPath: "/tmp/Brave Root", isDirectory: true)
    let json = """
      {"profile": {"info_cache": {
        "Default": {"name": "Personal"},
        "Profile 3": {"name": "  "},
        "Profile 1": {"name": "Work"},
        "../escape": {"name": "Escape"},
        "a/b": {"name": "Nested"}
      }}}
      """

    let profiles = try ChromiumLocalStateParser.parse(Data(json.utf8), userDataDirectory: root)

    XCTAssertEqual(profiles.map(\.name), ["Personal", "Profile 3", "Work"])
    XCTAssertEqual(profiles.map(\.directory), ["Default", "Profile 3", "Profile 1"])
    XCTAssertEqual(profiles[2].path.path, "/tmp/Brave Root/Profile 1")
  }

  func testParserRejectsLocalStateWithoutProfileList() {
    for json in ["{}", "{\"profile\": {}}", "[]", "not json"] {
      XCTAssertThrowsError(
        try ChromiumLocalStateParser.parse(
          Data(json.utf8), userDataDirectory: URL(fileURLWithPath: "/tmp")), json)
    }
  }

  func testDiscoveryKeepsExistingProfilesAndWarnsAboutMissingOnes() throws {
    let support = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: support) }
    let userData = support.appendingPathComponent(brave.userDataPath, isDirectory: true)
    try FileManager.default.createDirectory(
      at: userData.appendingPathComponent("Profile 1"), withIntermediateDirectories: true)
    try Data(
      #"{"profile": {"info_cache": {"Profile 1": {"name": "Work"}, "Profile 2": {"name": "Gone"}}}}"#
        .utf8
    ).write(to: userData.appendingPathComponent("Local State"))

    let result = ChromiumProfileDiscovery(applicationSupport: support).discover(brave)

    XCTAssertEqual(result.profiles.map(\.name), ["Work"])
    XCTAssertEqual(result.profiles.first?.path, userData.appendingPathComponent("Profile 1").standardizedFileURL)
    XCTAssertEqual(result.warnings.count, 1)
    XCTAssertTrue(result.warnings[0].contains("Ignored missing Brave profile"))
    XCTAssertFalse(result.needsAccess)
  }

  func testDiscoveryIsQuietWhenBrowserHasNeverRunAndWarnsOnCorruptState() throws {
    let support = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: support) }
    let discovery = ChromiumProfileDiscovery(applicationSupport: support)

    let neverRun = discovery.discover(brave)
    XCTAssertTrue(neverRun.profiles.isEmpty)
    XCTAssertTrue(neverRun.warnings.isEmpty)
    XCTAssertFalse(neverRun.needsAccess)

    let userData = support.appendingPathComponent(brave.userDataPath, isDirectory: true)
    try FileManager.default.createDirectory(at: userData, withIntermediateDirectories: true)
    try Data("{".utf8).write(to: userData.appendingPathComponent("Local State"))
    let corrupt = discovery.discover(brave)
    XCTAssertTrue(corrupt.profiles.isEmpty)
    XCTAssertEqual(corrupt.warnings.count, 1)
    XCTAssertFalse(corrupt.needsAccess)
  }

  func testDiscoveryRequestsAccessWhenLocalStateIsUnreadable() throws {
    let support = try makeTemporaryDirectory()
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: support.appendingPathComponent(brave.userDataPath).path)
      try? FileManager.default.removeItem(at: support)
    }
    let userData = support.appendingPathComponent(brave.userDataPath, isDirectory: true)
    try FileManager.default.createDirectory(at: userData, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: userData.appendingPathComponent("Local State"))
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: userData.path)

    let discovery = ChromiumProfileDiscovery(applicationSupport: support)
    let result = discovery.discover(brave)

    XCTAssertTrue(result.needsAccess)
    XCTAssertEqual(discovery.folder(for: brave).url, userData)
  }

  func testBuilderReplacesChromiumApplicationWithItsProfiles() {
    let chrome = BrowserApplicationRecord(
      bundleIdentifier: "com.google.Chrome",
      appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"), displayName: "Google Chrome")
    let braveApp = BrowserApplicationRecord(
      bundleIdentifier: brave.bundleIdentifier,
      appURL: URL(fileURLWithPath: "/Applications/Brave Browser.app"), displayName: "Brave Browser")
    let userData = URL(fileURLWithPath: "/Support/Google/Chrome", isDirectory: true)
    let profiles = [
      ChromiumProfile(name: "Personal", directory: "Default", userDataDirectory: userData),
      ChromiumProfile(name: "Work", directory: "Profile 1", userDataDirectory: userData),
    ]

    let targets = BrowserTargetBuilder.build(
      applications: [chrome, braveApp], currentBundleIdentifier: "self", firefoxProfiles: [],
      chromiumProfiles: [chrome.bundleIdentifier: profiles, brave.bundleIdentifier: []]
    ).targets

    XCTAssertEqual(targets.map(\.displayName), ["Personal", "Work", "Brave Browser"])
    XCTAssertEqual(
      targets.map(\.id),
      ["com.google.Chrome|chromium|Default", "com.google.Chrome|chromium|Profile 1",
       "com.brave.Browser|application"])
    XCTAssertEqual(
      targets[1].kind, .chromiumProfile(userDataDirectory: userData, directory: "Profile 1"))
    XCTAssertEqual(targets[1].appURL, chrome.appURL)
    XCTAssertEqual(targets[2].kind, .application)
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("BrowserSelectorChromiumTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
