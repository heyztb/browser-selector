// Copyright (c) 2026 Zach Blake
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

struct BrowserApplicationRecord: Equatable, Sendable {
  let bundleIdentifier: String
  let appURL: URL
  let displayName: String
}

enum BrowserTargetBuilder {
  static let firefoxBundleIdentifiers: Set<String> = [
    "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
  ]

  static func build(
    applications: [BrowserApplicationRecord],
    currentBundleIdentifier: String,
    firefoxProfiles: [FirefoxProfile],
    chromiumProfiles: [String: [ChromiumProfile]] = [:]
  ) -> DiscoveryResult {
    var seen: Set<String> = []
    var targets: [BrowserTarget] = []

    let firefoxApplications = applications.filter {
      firefoxBundleIdentifiers.contains($0.bundleIdentifier)
    }
    var profilesByBundle:
      [String: [(profile: FirefoxProfile, application: BrowserApplicationRecord)]] = [:]
    var warnings: [String] = []
    for profile in firefoxProfiles {
      let matches = firefoxApplications.filter { profile.compatibility.matches($0) }
      let bundles = Set(matches.map(\.bundleIdentifier))
      if bundles.count == 1, let match = matches.first {
        profilesByBundle[match.bundleIdentifier, default: []].append((profile, match))
      } else {
        warnings.append(
          "Skipped Firefox profile \(profile.name) (\(profile.path.path)): its recorded app could not be matched. Open the profile in its intended Firefox edition, then refresh."
        )
      }
    }

    for application in applications {
      let bundleIdentifier = application.bundleIdentifier
      guard bundleIdentifier != currentBundleIdentifier,
        seen.insert(bundleIdentifier).inserted
      else { continue }

      if let profiles = profilesByBundle[bundleIdentifier], !profiles.isEmpty {
        for (profile, matchedApplication) in profiles {
          targets.append(
            BrowserTarget(
              id: BrowserTarget.firefoxProfileID(
                bundleIdentifier: bundleIdentifier, path: profile.path),
              bundleIdentifier: bundleIdentifier,
              appURL: matchedApplication.appURL.standardizedFileURL,
              discoveredName: profile.name,
              kind: .firefoxProfile(path: profile.path),
              customName: nil,
              isVisible: true,
              order: targets.count
            ))
        }
      } else if let profiles = chromiumProfiles[bundleIdentifier], !profiles.isEmpty {
        for profile in profiles {
          targets.append(
            BrowserTarget(
              id: BrowserTarget.chromiumProfileID(
                bundleIdentifier: bundleIdentifier, directory: profile.directory),
              bundleIdentifier: bundleIdentifier,
              appURL: application.appURL.standardizedFileURL,
              discoveredName: profile.name,
              kind: .chromiumProfile(
                userDataDirectory: profile.userDataDirectory, directory: profile.directory),
              customName: nil,
              isVisible: true,
              order: targets.count
            ))
        }
      } else {
        targets.append(
          BrowserTarget(
            id: BrowserTarget.applicationID(bundleIdentifier: bundleIdentifier),
            bundleIdentifier: bundleIdentifier,
            appURL: application.appURL.standardizedFileURL,
            discoveredName: application.displayName,
            kind: .application,
            customName: nil,
            isVisible: true,
            order: targets.count
          ))
      }
    }
    return DiscoveryResult(targets: targets, warnings: warnings)
  }
}

@MainActor
protocol BrowserDiscovering {
  func discover() -> DiscoveryResult
}

@MainActor
final class BrowserDiscovery: BrowserDiscovering {
  private let workspace: NSWorkspace
  private let currentBundleIdentifier: String
  private let firefoxProfiles: FirefoxProfileDiscovery
  private let chromiumProfiles: ChromiumProfileDiscovery

  init(
    workspace: NSWorkspace = .shared,
    currentBundleIdentifier: String = Bundle.main.bundleIdentifier
      ?? "io.github.heyztb.BrowserSelector",
    firefoxProfiles: FirefoxProfileDiscovery = FirefoxProfileDiscovery(),
    chromiumProfiles: ChromiumProfileDiscovery = ChromiumProfileDiscovery()
  ) {
    self.workspace = workspace
    self.currentBundleIdentifier = currentBundleIdentifier
    self.firefoxProfiles = firefoxProfiles
    self.chromiumProfiles = chromiumProfiles
  }

  func discover() -> DiscoveryResult {
    guard let probeURL = URL(string: "https://example.invalid") else {
      return DiscoveryResult(
        targets: [], warnings: ["Could not construct the browser discovery URL."])
    }

    var applications: [BrowserApplicationRecord] = []
    var warnings: [String] = []

    for appURL in workspace.urlsForApplications(toOpen: probeURL) {
      guard let bundle = Bundle(url: appURL),
        let bundleIdentifier = bundle.bundleIdentifier
      else { continue }

      let appName =
        (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
        ?? appURL.deletingPathExtension().lastPathComponent

      applications.append(
        BrowserApplicationRecord(
          bundleIdentifier: bundleIdentifier,
          appURL: appURL.standardizedFileURL,
          displayName: appName
        ))
    }

    var foldersNeedingAccess: [ProfileFolder] = []
    let firefoxResult =
      applications.contains {
        BrowserTargetBuilder.firefoxBundleIdentifiers.contains($0.bundleIdentifier)
      }
      ? firefoxProfiles.discover() : (profiles: [], warnings: [], needsAccess: false)
    warnings.append(contentsOf: firefoxResult.warnings)
    if firefoxResult.needsAccess { foldersNeedingAccess.append(firefoxProfiles.folder) }

    var chromiumResults: [String: [ChromiumProfile]] = [:]
    for browser in ChromiumBrowser.known
    where applications.contains(where: { $0.bundleIdentifier == browser.bundleIdentifier }) {
      let result = chromiumProfiles.discover(browser)
      chromiumResults[browser.bundleIdentifier] = result.profiles
      warnings.append(contentsOf: result.warnings)
      if result.needsAccess { foldersNeedingAccess.append(chromiumProfiles.folder(for: browser)) }
    }

    let result = BrowserTargetBuilder.build(
      applications: applications,
      currentBundleIdentifier: currentBundleIdentifier,
      firefoxProfiles: firefoxResult.profiles,
      chromiumProfiles: chromiumResults
    )

    warnings.append(contentsOf: result.warnings)
    if result.targets.isEmpty {
      warnings.append("No installed web browsers were found.")
    }
    return DiscoveryResult(
      targets: result.targets, warnings: warnings, foldersNeedingAccess: foldersNeedingAccess)
  }
}

enum TargetReconciler {
  static func reconcile(
    discovered: [BrowserTarget],
    preferences: [String: TargetPreferences]
  ) -> [BrowserTarget] {
    var targets = discovered.map { target in
      var target = target
      let legacyID: String? = {
        guard target.bundleIdentifier == "org.mozilla.firefoxdeveloperedition",
          let path = target.profilePath
        else { return nil }
        return BrowserTarget.firefoxProfileID(bundleIdentifier: "org.mozilla.firefox", path: path)
      }()
      if let preference = preferences[target.id] ?? legacyID.flatMap({ preferences[$0] }) {
        target.customName = preference.customName
        target.isVisible = preference.isVisible
        target.order = preference.order
      } else {
        target.order = Int.max
      }
      return target
    }

    targets.sort {
      if $0.order != $1.order { return $0.order < $1.order }
      let nameOrder = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
      return nameOrder == .orderedSame ? $0.id < $1.id : nameOrder == .orderedAscending
    }
    for index in targets.indices {
      targets[index].order = index
    }
    return targets
  }

  static func preferences(from targets: [BrowserTarget]) -> [String: TargetPreferences] {
    Dictionary(
      uniqueKeysWithValues: targets.enumerated().map { index, target in
        (
          target.id,
          TargetPreferences(
            customName: target.customName,
            isVisible: target.isVisible,
            order: index
          )
        )
      })
  }
}
