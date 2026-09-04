import AppKit
import Foundation

struct BrowserApplicationRecord: Equatable, Sendable {
  let bundleIdentifier: String
  let appURL: URL
  let displayName: String
}

enum BrowserTargetBuilder {
  static func build(
    applications: [BrowserApplicationRecord],
    currentBundleIdentifier: String,
    firefoxProfiles: [FirefoxProfile]
  ) -> [BrowserTarget] {
    var seen: Set<String> = []
    var targets: [BrowserTarget] = []

    for application in applications {
      let bundleIdentifier = application.bundleIdentifier
      guard bundleIdentifier != currentBundleIdentifier,
        seen.insert(bundleIdentifier).inserted
      else { continue }

      if bundleIdentifier == "org.mozilla.firefox", !firefoxProfiles.isEmpty {
        for profile in firefoxProfiles {
          targets.append(
            BrowserTarget(
              id: BrowserTarget.firefoxProfileID(
                bundleIdentifier: bundleIdentifier, path: profile.path),
              bundleIdentifier: bundleIdentifier,
              appURL: application.appURL.standardizedFileURL,
              discoveredName: profile.name,
              kind: .firefoxProfile(path: profile.path),
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
    return targets
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

  init(
    workspace: NSWorkspace = .shared,
    currentBundleIdentifier: String = Bundle.main.bundleIdentifier
      ?? "io.github.heyztb.BrowserSelector",
    firefoxProfiles: FirefoxProfileDiscovery = FirefoxProfileDiscovery()
  ) {
    self.workspace = workspace
    self.currentBundleIdentifier = currentBundleIdentifier
    self.firefoxProfiles = firefoxProfiles
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

    let profileResult =
      applications.contains { $0.bundleIdentifier == "org.mozilla.firefox" }
      ? firefoxProfiles.discover() : (profiles: [], warnings: [])
    warnings.append(contentsOf: profileResult.warnings)
    let targets = BrowserTargetBuilder.build(
      applications: applications,
      currentBundleIdentifier: currentBundleIdentifier,
      firefoxProfiles: profileResult.profiles
    )

    if targets.isEmpty {
      warnings.append("No installed web browsers were found.")
    }
    return DiscoveryResult(targets: targets, warnings: warnings)
  }
}

enum TargetReconciler {
  static func reconcile(
    discovered: [BrowserTarget],
    preferences: [String: TargetPreferences]
  ) -> [BrowserTarget] {
    var targets = discovered.map { target in
      var target = target
      if let preference = preferences[target.id] {
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
