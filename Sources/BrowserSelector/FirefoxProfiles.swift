// Copyright (c) 2026 Zach Blake
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct FirefoxProfile: Equatable, Sendable {
  let name: String
  let path: URL
  let isRegistered: Bool
  var compatibility: FirefoxCompatibility = FirefoxCompatibility()
}

struct FirefoxCompatibility: Equatable, Sendable {
  var lastPlatformDirectory: String?
  var lastAppDirectory: String?

  static func parse(_ contents: String) -> Self {
    var result = Self()
    var inCompatibility = false
    for rawLine in contents.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.hasPrefix("[") {
        inCompatibility = line == "[Compatibility]"
      } else if inCompatibility, let separator = line.firstIndex(of: "=") {
        let key = line[..<separator].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        if key == "LastPlatformDir" { result.lastPlatformDirectory = value }
        if key == "LastAppDir" { result.lastAppDirectory = value }
      }
    }
    return result
  }

  func matches(_ application: BrowserApplicationRecord) -> Bool {
    func matchesPath(_ raw: String, _ suffix: String) -> Bool {
      guard NSString(string: raw).isAbsolutePath else { return false }
      return URL(fileURLWithPath: raw).standardizedFileURL.resolvingSymlinksInPath().path
        == application.appURL.appendingPathComponent(suffix)
        .standardizedFileURL.resolvingSymlinksInPath().path
    }
    if let platform = lastPlatformDirectory {
      guard matchesPath(platform, "Contents/Resources") else { return false }
      return lastAppDirectory.map { matchesPath($0, "Contents/Resources/browser") } ?? true
    }
    return lastAppDirectory.map { matchesPath($0, "Contents/Resources/browser") } ?? false
  }
}

enum FirefoxProfileParser {
  static func parse(_ contents: String, firefoxRoot: URL) -> [FirefoxProfile] {
    var profiles: [FirefoxProfile] = []
    var section: String?
    var values: [String: String] = [:]

    func flush() {
      guard section?.hasPrefix("Profile") == true,
        let rawName = clean(values["Name"]),
        let rawPath = clean(values["Path"])
      else { return }

      let isRelative = values["IsRelative"] != "0"
      let path =
        isRelative
        ? firefoxRoot.appendingPathComponent(rawPath, isDirectory: true)
        : URL(fileURLWithPath: NSString(string: rawPath).expandingTildeInPath, isDirectory: true)
      profiles.append(
        FirefoxProfile(
          name: rawName,
          path: path.standardizedFileURL,
          isRegistered: true
        ))
    }

    for rawLine in contents.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else { continue }

      if line.hasPrefix("["), line.hasSuffix("]") {
        flush()
        section = String(line.dropFirst().dropLast())
        values.removeAll(keepingCapacity: true)
        continue
      }

      guard let separator = line.firstIndex(of: "=") else { continue }
      let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
      let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
      values[key] = value
    }
    flush()
    return profiles
  }

  private static func clean(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else {
      return nil
    }
    return trimmed
  }
}

struct FirefoxProfileDiscovery {
  let fileManager: FileManager
  let firefoxRoot: URL

  init(fileManager: FileManager = .default, firefoxRoot: URL? = nil) {
    self.fileManager = fileManager
    self.firefoxRoot =
      firefoxRoot
      ?? fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/Firefox", isDirectory: true)
  }

  func discover() -> (profiles: [FirefoxProfile], warnings: [String]) {
    var warnings: [String] = []
    var byPath: [String: FirefoxProfile] = [:]
    let iniURL = firefoxRoot.appendingPathComponent("profiles.ini")

    if fileManager.fileExists(atPath: iniURL.path) {
      do {
        let contents = try String(contentsOf: iniURL, encoding: .utf8)
        for profile in FirefoxProfileParser.parse(contents, firefoxRoot: firefoxRoot) {
          guard isProfileDirectory(profile.path) else {
            warnings.append("Ignored missing Firefox profile: \(profile.path.path)")
            continue
          }
          byPath[profile.path.standardizedFileURL.path] = profile
        }
      } catch {
        warnings.append("Could not read Firefox profiles.ini: \(error.localizedDescription)")
      }
    }

    let profilesDirectory = firefoxRoot.appendingPathComponent("Profiles", isDirectory: true)
    do {
      let directories = try fileManager.contentsOfDirectory(
        at: profilesDirectory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
      for directory in directories where isProfileDirectory(directory) {
        let path = directory.standardizedFileURL.path
        if byPath[path] == nil {
          byPath[path] = FirefoxProfile(
            name: directory.lastPathComponent,
            path: directory.standardizedFileURL,
            isRegistered: false
          )
        }
      }
    } catch {
      if (error as NSError).code != NSFileReadNoSuchFileError {
        warnings.append("Could not scan Firefox profiles: \(error.localizedDescription)")
      }
    }

    let profiles = byPath.values.map { profile in
      var profile = profile
      if let contents = try? String(
        contentsOf: profile.path.appendingPathComponent("compatibility.ini"), encoding: .utf8
      ) {
        profile.compatibility = FirefoxCompatibility.parse(contents)
      }
      return profile
    }.sorted {
      let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
      return comparison == .orderedSame
        ? $0.path.path < $1.path.path : comparison == .orderedAscending
    }
    return (profiles, warnings)
  }

  private func isProfileDirectory(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue
    else {
      return false
    }

    return ["prefs.js", "times.json", "compatibility.ini", "places.sqlite"].contains {
      fileManager.fileExists(atPath: url.appendingPathComponent($0).path)
    }
  }
}
