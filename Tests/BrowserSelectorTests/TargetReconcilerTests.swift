import Foundation
import XCTest

@testable import BrowserSelector

final class TargetReconcilerTests: XCTestCase {
  func testPreferencesSurviveRediscoveryAndNewTargetsAppend() {
    let safari = target(id: "safari", name: "Safari", order: 0)
    let tor = target(id: "tor", name: "Tor Browser", order: 1)
    let preferences = [
      "tor": TargetPreferences(customName: "Private", isVisible: true, order: 0),
      "safari": TargetPreferences(customName: nil, isVisible: false, order: 1),
    ]

    let result = TargetReconciler.reconcile(
      discovered: [safari, tor, target(id: "orion", name: "Orion", order: 2)],
      preferences: preferences
    )

    XCTAssertEqual(result.map(\.id), ["tor", "safari", "orion"])
    XCTAssertEqual(result[0].displayName, "Private")
    XCTAssertFalse(result[1].isVisible)
    XCTAssertEqual(result.map(\.order), [0, 1, 2])
  }

  func testStableFirefoxIDUsesStandardizedAbsolutePath() {
    let id = BrowserTarget.firefoxProfileID(
      bundleIdentifier: "org.mozilla.firefox",
      path: URL(fileURLWithPath: "/tmp/Profiles/../Profiles/Profile 1")
    )
    XCTAssertEqual(id, "org.mozilla.firefox|firefox|/tmp/Profiles/Profile 1")
  }

  private func target(id: String, name: String, order: Int) -> BrowserTarget {
    BrowserTarget(
      id: id,
      bundleIdentifier: "example.\(id)",
      appURL: URL(fileURLWithPath: "/Applications/\(name).app"),
      discoveredName: name,
      kind: .application,
      customName: nil,
      isVisible: true,
      order: order
    )
  }
}
