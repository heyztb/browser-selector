import Foundation
import XCTest

@testable import BrowserSelector

@MainActor
final class TargetStoreTests: XCTestCase {
  func testStorePersistsRenameVisibilityAndOrderAcrossRediscovery() throws {
    let suiteName = "BrowserSelectorTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let discovery = StubDiscovery(targets: [target("one"), target("two"), target("three")])
    let store = TargetStore(discovery: discovery, defaults: defaults)

    store.setCustomName("Personal", for: "two")
    store.setVisible(false, for: "one")
    store.moveTarget(id: "three", direction: -1)

    let restored = TargetStore(discovery: discovery, defaults: defaults)
    XCTAssertEqual(restored.targets.map(\.id), ["three", "one", "two"])
    XCTAssertFalse(try XCTUnwrap(restored.targets.first { $0.id == "one" }).isVisible)
    XCTAssertEqual(try XCTUnwrap(restored.targets.first { $0.id == "two" }).displayName, "Personal")
  }

  func testStoreRefusesToDisableFinalVisibleTarget() {
    let suiteName = "BrowserSelectorTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = TargetStore(discovery: StubDiscovery(targets: [target("only")]), defaults: defaults)

    store.setVisible(false, for: "only")

    XCTAssertEqual(store.visibleTargets.map(\.id), ["only"])
  }

  func testTemporarilyMissingTargetKeepsItsPreferences() throws {
    let suiteName = "BrowserSelectorTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let discovery = StubDiscovery(targets: [target("one"), target("two")])
    let store = TargetStore(discovery: discovery, defaults: defaults)
    store.setCustomName("Work", for: "two")

    discovery.targets = [target("one")]
    store.refresh()
    discovery.targets = [target("one"), target("two")]
    store.refresh()

    XCTAssertEqual(try XCTUnwrap(store.targets.first { $0.id == "two" }).displayName, "Work")
  }

  private func target(_ id: String) -> BrowserTarget {
    BrowserTarget(
      id: id,
      bundleIdentifier: "example.\(id)",
      appURL: URL(fileURLWithPath: "/Applications/\(id).app"),
      discoveredName: id,
      kind: .application,
      customName: nil,
      isVisible: true,
      order: 0
    )
  }
}

@MainActor
private final class StubDiscovery: BrowserDiscovering {
  var targets: [BrowserTarget]

  init(targets: [BrowserTarget]) {
    self.targets = targets
  }

  func discover() -> DiscoveryResult {
    DiscoveryResult(targets: targets, warnings: [])
  }
}
