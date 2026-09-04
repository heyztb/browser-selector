import Foundation

struct BrowserTarget: Identifiable, Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case application
    case firefoxProfile(path: URL)
  }

  let id: String
  let bundleIdentifier: String
  let appURL: URL
  let discoveredName: String
  let kind: Kind
  var customName: String?
  var isVisible: Bool
  var order: Int

  var displayName: String {
    let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.flatMap { $0.isEmpty ? nil : $0 } ?? discoveredName
  }

  var profilePath: URL? {
    guard case .firefoxProfile(let path) = kind else { return nil }
    return path
  }

  static func applicationID(bundleIdentifier: String) -> String {
    "\(bundleIdentifier)|application"
  }

  static func firefoxProfileID(bundleIdentifier: String, path: URL) -> String {
    "\(bundleIdentifier)|firefox|\(path.standardizedFileURL.path)"
  }
}

struct TargetPreferences: Codable, Equatable, Sendable {
  var customName: String?
  var isVisible: Bool
  var order: Int
}

struct DiscoveryResult: Equatable, Sendable {
  var targets: [BrowserTarget]
  var warnings: [String]
}

enum BrowserLaunchError: LocalizedError, Equatable, Sendable {
  case noURLs
  case applicationMissing(String)
  case executableMissing(String)
  case profileMissing(String)
  case launchFailed(String)

  var errorDescription: String? {
    switch self {
    case .noURLs:
      "There are no links to open."
    case .applicationMissing(let name):
      "\(name) is no longer installed. Refresh the browser list in Settings."
    case .executableMissing(let name):
      "The executable inside \(name) could not be found."
    case .profileMissing(let path):
      "The Firefox profile no longer exists at \(path)."
    case .launchFailed(let message):
      "The browser could not be opened: \(message)"
    }
  }
}
