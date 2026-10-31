// Copyright (c) 2026 Zach Blake
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A Chromium-based browser whose profiles can be targeted with `--profile-directory`.
struct ChromiumBrowser: Equatable, Sendable {
  let bundleIdentifier: String
  let name: String
  /// User data directory, relative to `~/Library/Application Support`.
  let userDataPath: String

  static let known: [ChromiumBrowser] = [
    ChromiumBrowser(bundleIdentifier: "com.google.Chrome", name: "Google Chrome", userDataPath: "Google/Chrome"),
    ChromiumBrowser(
      bundleIdentifier: "com.google.Chrome.beta", name: "Google Chrome Beta",
      userDataPath: "Google/Chrome Beta"),
    ChromiumBrowser(
      bundleIdentifier: "com.google.Chrome.dev", name: "Google Chrome Dev",
      userDataPath: "Google/Chrome Dev"),
    ChromiumBrowser(
      bundleIdentifier: "com.google.Chrome.canary", name: "Google Chrome Canary",
      userDataPath: "Google/Chrome Canary"),
    ChromiumBrowser(bundleIdentifier: "org.chromium.Chromium", name: "Chromium", userDataPath: "Chromium"),
    ChromiumBrowser(
      bundleIdentifier: "com.brave.Browser", name: "Brave", userDataPath: "BraveSoftware/Brave-Browser"),
    ChromiumBrowser(
      bundleIdentifier: "com.brave.Browser.beta", name: "Brave Beta",
      userDataPath: "BraveSoftware/Brave-Browser-Beta"),
    ChromiumBrowser(
      bundleIdentifier: "com.brave.Browser.nightly", name: "Brave Nightly",
      userDataPath: "BraveSoftware/Brave-Browser-Nightly"),
    ChromiumBrowser(
      bundleIdentifier: "com.microsoft.edgemac", name: "Microsoft Edge", userDataPath: "Microsoft Edge"),
    ChromiumBrowser(
      bundleIdentifier: "com.microsoft.edgemac.Beta", name: "Microsoft Edge Beta",
      userDataPath: "Microsoft Edge Beta"),
    ChromiumBrowser(
      bundleIdentifier: "com.microsoft.edgemac.Dev", name: "Microsoft Edge Dev",
      userDataPath: "Microsoft Edge Dev"),
    ChromiumBrowser(
      bundleIdentifier: "com.microsoft.edgemac.Canary", name: "Microsoft Edge Canary",
      userDataPath: "Microsoft Edge Canary"),
    ChromiumBrowser(bundleIdentifier: "com.vivaldi.Vivaldi", name: "Vivaldi", userDataPath: "Vivaldi"),
  ]

  static func browser(bundleIdentifier: String) -> ChromiumBrowser? {
    known.first { $0.bundleIdentifier == bundleIdentifier }
  }
}

struct ChromiumProfile: Equatable, Sendable {
  let name: String
  /// Profile directory name inside the user data directory, such as `Default` or `Profile 1`.
  let directory: String
  let userDataDirectory: URL

  var path: URL {
    userDataDirectory.appendingPathComponent(directory, isDirectory: true).standardizedFileURL
  }
}

enum ChromiumLocalStateParser {
  struct MalformedLocalState: LocalizedError {
    var errorDescription: String? { "Local State has no profile list." }
  }

  /// Reads `profile.info_cache` from a Chromium `Local State` file.
  static func parse(_ data: Data, userDataDirectory: URL) throws -> [ChromiumProfile] {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let profile = root["profile"] as? [String: Any],
      let cache = profile["info_cache"] as? [String: Any]
    else { throw MalformedLocalState() }

    return cache.compactMap { directory, value in
      guard isPlainDirectoryName(directory), let entry = value as? [String: Any] else { return nil }
      let rawName = (entry["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      let name = rawName.flatMap { $0.isEmpty ? nil : $0 } ?? directory
      return ChromiumProfile(
        name: name, directory: directory, userDataDirectory: userDataDirectory.standardizedFileURL)
    }.sorted {
      let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
      return comparison == .orderedSame
        ? $0.directory < $1.directory : comparison == .orderedAscending
    }
  }

  private static func isPlainDirectoryName(_ name: String) -> Bool {
    !name.isEmpty && name != "." && name != ".." && !name.contains("/")
  }
}

struct ChromiumProfileDiscovery {
  let fileManager: FileManager
  let applicationSupport: URL

  init(fileManager: FileManager = .default, applicationSupport: URL? = nil) {
    self.fileManager = fileManager
    self.applicationSupport =
      applicationSupport
      ?? fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support", isDirectory: true)
  }

  func folder(for browser: ChromiumBrowser) -> ProfileFolder {
    ProfileFolder(
      browserName: browser.name,
      url: applicationSupport.appendingPathComponent(browser.userDataPath, isDirectory: true),
      bookmarkKey: "chromiumFolderBookmark.v1|\(browser.bundleIdentifier)")
  }

  func discover(_ browser: ChromiumBrowser) -> (
    profiles: [ChromiumProfile], warnings: [String], needsAccess: Bool
  ) {
    let folder = folder(for: browser)
    let scopedURL = FolderAuthorization.startAccessing(folder)
    defer { scopedURL?.stopAccessingSecurityScopedResource() }

    let data: Data
    do {
      data = try Data(contentsOf: folder.url.appendingPathComponent("Local State"))
    } catch {
      // A browser that has never been opened has no Local State yet.
      if (error as NSError).code == NSFileReadNoSuchFileError { return ([], [], false) }
      return (
        [], ["Could not read \(browser.name) profiles: \(error.localizedDescription)"],
        FolderAuthorization.isPermissionError(error)
      )
    }

    let parsed: [ChromiumProfile]
    do {
      parsed = try ChromiumLocalStateParser.parse(data, userDataDirectory: folder.url)
    } catch {
      return ([], ["Could not read \(browser.name) profiles: \(error.localizedDescription)"], false)
    }

    var warnings: [String] = []
    let profiles = parsed.filter { profile in
      var isDirectory: ObjCBool = false
      guard fileManager.fileExists(atPath: profile.path.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      else {
        warnings.append("Ignored missing \(browser.name) profile: \(profile.path.path)")
        return false
      }
      return true
    }
    return (profiles, warnings, false)
  }
}
