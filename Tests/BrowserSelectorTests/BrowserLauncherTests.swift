// Copyright (c) 2026 Zach Blake
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import XCTest

@testable import BrowserSelector

@MainActor
final class BrowserLauncherTests: XCTestCase {
  func testGenericBrowserUsesWorkspaceWithAllURLs() throws {
    let appURL = try makeFakeApplication(executableName: "Fake")
    defer { try? FileManager.default.removeItem(at: appURL.deletingLastPathComponent()) }
    let workspace = RecordingWorkspace()
    let launcher = BrowserLauncher(workspace: workspace)
    let urls = [URL(string: "https://one.example")!, URL(string: "https://two.example")!]
    let target = makeTarget(appURL: appURL, kind: .application)
    let recorder = LaunchResultRecorder()

    launcher.open(urls: urls, with: target) { recorder.result = $0 }

    XCTAssertEqual(workspace.openedURLs, urls)
    XCTAssertEqual(workspace.applicationURL, appURL)
    XCTAssertNotNil(try recorder.result?.get())
  }

  func testFirefoxUsesAbsoluteProfileArgumentWithoutShellOrNoRemote() throws {
    let appURL = try makeFakeApplication(executableName: "firefox")
    defer { try? FileManager.default.removeItem(at: appURL.deletingLastPathComponent()) }
    let profile = appURL.deletingLastPathComponent().appendingPathComponent("xADZmP5H.Profile 1")
    try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
    let runner = RecordingProcessRunner()
    let launcher = BrowserLauncher(processRunner: runner)
    let urls = [URL(string: "https://example.com/a?b=c")!]
    let target = makeTarget(appURL: appURL, kind: .firefoxProfile(path: profile))
    let recorder = LaunchResultRecorder()

    launcher.open(urls: urls, with: target) { recorder.result = $0 }

    XCTAssertNotNil(try recorder.result?.get())
    XCTAssertEqual(
      runner.arguments, ["-profile", profile.standardizedFileURL.path, urls[0].absoluteString])
    XCTAssertFalse(runner.arguments?.contains("-no-remote") == true)
    XCTAssertEqual(runner.executableURL?.lastPathComponent, "firefox")
  }

  func testDeveloperProfileUsesMatchedExecutable() throws {
    let appURL = try makeFakeApplication(executableName: "firefox")
    defer { try? FileManager.default.removeItem(at: appURL.deletingLastPathComponent()) }
    let profileURL = appURL.deletingLastPathComponent().appendingPathComponent("Dev Profile")
    try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
    let application = BrowserApplicationRecord(
      bundleIdentifier: "org.mozilla.firefoxdeveloperedition",
      appURL: appURL, displayName: "Firefox Developer Edition")
    let profile = FirefoxProfile(
      name: "dev", path: profileURL, isRegistered: true,
      compatibility: FirefoxCompatibility(
        lastPlatformDirectory: appURL.path + "/Contents/Resources"))
    let result = BrowserTargetBuilder.build(
      applications: [application],
      currentBundleIdentifier: "self", firefoxProfiles: [profile])
    let target = try XCTUnwrap(result.targets.first)
    let runner = RecordingProcessRunner()
    let recorder = LaunchResultRecorder()
    BrowserLauncher(processRunner: runner).open(
      urls: [URL(string: "https://example.com")!], with: target
    ) {
      recorder.result = $0
    }
    XCTAssertNotNil(try recorder.result?.get())
    XCTAssertEqual(runner.executableURL, appURL.appendingPathComponent("Contents/MacOS/firefox"))
    XCTAssertEqual(runner.arguments, ["-profile", profileURL.path, "https://example.com"])
  }

  func testMissingProfileReturnsActionableFailureWithoutRunning() throws {
    let appURL = try makeFakeApplication(executableName: "firefox")
    defer { try? FileManager.default.removeItem(at: appURL.deletingLastPathComponent()) }
    let runner = RecordingProcessRunner()
    let launcher = BrowserLauncher(processRunner: runner)
    let missing = URL(fileURLWithPath: "/definitely/missing/profile")
    let target = makeTarget(appURL: appURL, kind: .firefoxProfile(path: missing))
    let recorder = LaunchResultRecorder()

    launcher.open(urls: [URL(string: "https://example.com")!], with: target) {
      recorder.result = $0
    }

    guard case .failure(let error) = recorder.result else {
      return XCTFail("Expected a missing-profile failure")
    }
    XCTAssertEqual(error, .profileMissing(missing.path))
    XCTAssertNil(runner.arguments)
  }

  private func makeTarget(appURL: URL, kind: BrowserTarget.Kind) -> BrowserTarget {
    BrowserTarget(
      id: "test",
      bundleIdentifier: "example.browser",
      appURL: appURL,
      discoveredName: "Browser",
      kind: kind,
      customName: nil,
      isVisible: true,
      order: 0
    )
  }

  private func makeFakeApplication(executableName: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "BrowserSelectorLauncherTests-\(UUID().uuidString)", isDirectory: true)
    let app = root.appendingPathComponent("Fake.app", isDirectory: true)
    let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
    try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
    let plist: [String: Any] = [
      "CFBundleIdentifier": "example.browser",
      "CFBundleExecutable": executableName,
      "CFBundlePackageType": "APPL",
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
    let executable = macOS.appendingPathComponent(executableName)
    XCTAssertTrue(
      FileManager.default.createFile(atPath: executable.path, contents: Data("#!/bin/sh\n".utf8)))
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    return app
  }
}

@MainActor
private final class RecordingWorkspace: WorkspaceOpening {
  var openedURLs: [URL]?
  var applicationURL: URL?

  func open(
    _ urls: [URL],
    withApplicationAt applicationURL: URL,
    configuration: NSWorkspace.OpenConfiguration,
    completionHandler: @escaping @MainActor @Sendable (String?) -> Void
  ) {
    openedURLs = urls
    self.applicationURL = applicationURL
    completionHandler(nil)
  }
}

@MainActor
private final class LaunchResultRecorder {
  var result: Result<Void, BrowserLaunchError>?
}

private final class RecordingProcessRunner: ProcessRunning, @unchecked Sendable {
  var executableURL: URL?
  var arguments: [String]?

  func run(executableURL: URL, arguments: [String]) throws {
    self.executableURL = executableURL
    self.arguments = arguments
  }
}
