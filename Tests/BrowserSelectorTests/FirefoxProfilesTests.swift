import Foundation
import XCTest

@testable import BrowserSelector

final class FirefoxProfilesTests: XCTestCase {
  func testParserHandlesRelativeAndAbsoluteProfilesAndSpaces() throws {
    let root = URL(fileURLWithPath: "/tmp/Firefox Root", isDirectory: true)
    let contents = """
      [General]
      StartWithLastProfile=1

      [Profile0]
      Name=Work Profile
      IsRelative=1
      Path=Profiles/l3a5ohf7.default-release

      [Profile1]
      Name=Personal
      IsRelative=0
      Path=/Volumes/Profiles/xADZmP5H.Profile 1
      """

    let profiles = FirefoxProfileParser.parse(contents, firefoxRoot: root)

    XCTAssertEqual(profiles.count, 2)
    XCTAssertEqual(profiles[0].name, "Work Profile")
    XCTAssertEqual(profiles[0].path.path, "/tmp/Firefox Root/Profiles/l3a5ohf7.default-release")
    XCTAssertEqual(profiles[1].path.path, "/Volumes/Profiles/xADZmP5H.Profile 1")
  }

  func testParserIgnoresMalformedAndNonProfileSections() {
    let contents = """
      [InstallABC]
      Name=Not a profile
      Path=Profiles/nope
      [Profile0]
      Name=Missing path
      [Profile1]
      Path=Profiles/missing-name
      """
    XCTAssertTrue(
      FirefoxProfileParser.parse(
        contents,
        firefoxRoot: URL(fileURLWithPath: "/tmp/firefox")
      ).isEmpty)
  }

  func testDiscoveryUnionsRegisteredAndOrphanDirectoriesWithoutDuplicates() throws {
    let temporary = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporary) }
    let profiles = temporary.appendingPathComponent("Profiles", isDirectory: true)
    let registered = profiles.appendingPathComponent("registered.default", isDirectory: true)
    let orphan = profiles.appendingPathComponent("xADZmP5H.Profile 1", isDirectory: true)
    try FileManager.default.createDirectory(at: registered, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
    XCTAssertTrue(
      FileManager.default.createFile(
        atPath: registered.appendingPathComponent("prefs.js").path, contents: Data()))
    XCTAssertTrue(
      FileManager.default.createFile(
        atPath: orphan.appendingPathComponent("times.json").path, contents: Data()))
    try """
    [Profile0]
    Name=Work
    IsRelative=1
    Path=Profiles/registered.default
    """.write(
      to: temporary.appendingPathComponent("profiles.ini"), atomically: true, encoding: .utf8)

    let result = FirefoxProfileDiscovery(firefoxRoot: temporary).discover()

    XCTAssertEqual(result.profiles.count, 2)
    XCTAssertEqual(Set(result.profiles.map(\.name)), ["Work", "xADZmP5H.Profile 1"])
    XCTAssertTrue(result.warnings.isEmpty)
  }

  func testDiscoveryReportsRegisteredMissingDirectory() throws {
    let temporary = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporary) }
    try """
    [Profile0]
    Name=Gone
    IsRelative=1
    Path=Profiles/gone.default
    """.write(
      to: temporary.appendingPathComponent("profiles.ini"), atomically: true, encoding: .utf8)

    let result = FirefoxProfileDiscovery(firefoxRoot: temporary).discover()

    XCTAssertTrue(result.profiles.isEmpty)
    XCTAssertTrue(result.warnings.contains { $0.contains("Ignored missing Firefox profile") })
  }

  private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("BrowserSelectorTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
