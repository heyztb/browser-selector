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
        isRegistered: true
      ),
      FirefoxProfile(
        name: "Work",
        path: URL(fileURLWithPath: "/Profiles/work"),
        isRegistered: false
      ),
    ]

    let targets = BrowserTargetBuilder.build(
      applications: applications,
      currentBundleIdentifier: "io.github.heyztb.BrowserSelector",
      firefoxProfiles: profiles
    )

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
    )
    XCTAssertEqual(targets.count, 1)
    XCTAssertEqual(targets[0].kind, .application)
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
