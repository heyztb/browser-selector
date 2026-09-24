// Copyright (c) 2026 Zach Blake
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest

@testable import BrowserSelector

@MainActor
final class PickerSessionTests: XCTestCase {
  func testFocusWrapsAndNumericSelectionIsExactlyOnce() {
    let session = PickerSession(
      urls: [URL(string: "https://example.com")!],
      targets: [target("one"), target("two"), target("three")]
    )

    session.moveFocus(by: -1)
    XCTAssertEqual(session.focusedIndex, 2)
    session.moveFocus(by: 1)
    XCTAssertEqual(session.focusedIndex, 0)

    let selection = session.select(index: 1)
    XCTAssertEqual(selection?.target.id, "two")
    XCTAssertNil(session.select(index: 2))
    XCTAssertFalse(session.cancel())
    session.finish(.success(()))
    XCTAssertTrue(session.hasCompleted)
  }

  func testFailureAllowsRetryAndKeepsError() {
    let session = PickerSession(
      urls: [URL(string: "https://example.com")!],
      targets: [target("one")]
    )
    XCTAssertNotNil(session.selectFocused())
    session.finish(.failure(.profileMissing("/missing")))
    XCTAssertNotNil(session.errorMessage)
    XCTAssertNotNil(session.selectFocused())
  }

  func testBatchesAcceptedURLsAndLabelsMixedBatchByCount() {
    let session = PickerSession(
      urls: [URL(string: "https://one.example/a")!, URL(string: "ftp://files.example/no")!],
      targets: [target("one")]
    )
    session.append(urls: [URL(string: "http://two.example/b")!])
    XCTAssertEqual(session.pendingURLs.count, 2)
    XCTAssertEqual(session.destinationLabel, "2 links")
  }

  func testAcceptsHTMLDocumentURLAndUsesFilenameAsLabel() {
    let session = PickerSession(
      urls: [URL(fileURLWithPath: "/tmp/example.html")],
      targets: [target("one")]
    )

    XCTAssertEqual(session.pendingURLs, [URL(fileURLWithPath: "/tmp/example.html")])
    XCTAssertEqual(session.destinationLabel, "example.html")
  }

  func testSingleURLUsesHostLabelAndCancelCompletes() {
    let session = PickerSession(
      urls: [URL(string: "https://example.com/path")!],
      targets: [target("one")]
    )
    XCTAssertEqual(session.destinationLabel, "example.com")
    XCTAssertTrue(session.cancel())
    XCTAssertFalse(session.cancel())
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
