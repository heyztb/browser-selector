import AppKit
import Foundation

@MainActor
protocol BrowserLaunching {
  func open(
    urls: [URL],
    with target: BrowserTarget,
    completion: @escaping @MainActor @Sendable (Result<Void, BrowserLaunchError>) -> Void
  )
}

@MainActor
protocol WorkspaceOpening {
  func open(
    _ urls: [URL],
    withApplicationAt applicationURL: URL,
    configuration: NSWorkspace.OpenConfiguration,
    completionHandler: @escaping @MainActor @Sendable (String?) -> Void
  )
}

@MainActor
final class LiveWorkspaceOpener: WorkspaceOpening {
  func open(
    _ urls: [URL],
    withApplicationAt applicationURL: URL,
    configuration: NSWorkspace.OpenConfiguration,
    completionHandler: @escaping @MainActor @Sendable (String?) -> Void
  ) {
    NSWorkspace.shared.open(
      urls,
      withApplicationAt: applicationURL,
      configuration: configuration
    ) { _, error in
      let message = error?.localizedDescription
      Task { @MainActor in completionHandler(message) }
    }
  }
}

protocol ProcessRunning: Sendable {
  func run(executableURL: URL, arguments: [String]) throws
}

struct FoundationProcessRunner: ProcessRunning {
  func run(executableURL: URL, arguments: [String]) throws {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    try process.run()
  }
}

@MainActor
final class BrowserLauncher: BrowserLaunching {
  private let workspace: WorkspaceOpening
  private let processRunner: ProcessRunning
  private let fileManager: FileManager

  init(
    workspace: WorkspaceOpening = LiveWorkspaceOpener(),
    processRunner: ProcessRunning = FoundationProcessRunner(),
    fileManager: FileManager = .default
  ) {
    self.workspace = workspace
    self.processRunner = processRunner
    self.fileManager = fileManager
  }

  func open(
    urls: [URL],
    with target: BrowserTarget,
    completion: @escaping @MainActor @Sendable (Result<Void, BrowserLaunchError>) -> Void
  ) {
    guard !urls.isEmpty else {
      completion(.failure(.noURLs))
      return
    }
    guard fileManager.fileExists(atPath: target.appURL.path) else {
      completion(.failure(.applicationMissing(target.displayName)))
      return
    }

    switch target.kind {
    case .application:
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      workspace.open(urls, withApplicationAt: target.appURL, configuration: configuration) {
        errorMessage in
        if let errorMessage {
          completion(.failure(.launchFailed(errorMessage)))
        } else {
          completion(.success(()))
        }
      }

    case .firefoxProfile(let profilePath):
      guard fileManager.fileExists(atPath: profilePath.path) else {
        completion(.failure(.profileMissing(profilePath.path)))
        return
      }
      guard let bundle = Bundle(url: target.appURL),
        let executableName = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
      else {
        completion(.failure(.executableMissing(target.displayName)))
        return
      }
      let executableURL = target.appURL
        .appendingPathComponent("Contents/MacOS", isDirectory: true)
        .appendingPathComponent(executableName)
      guard fileManager.isExecutableFile(atPath: executableURL.path) else {
        completion(.failure(.executableMissing(target.displayName)))
        return
      }

      do {
        try processRunner.run(
          executableURL: executableURL,
          arguments: ["-profile", profilePath.standardizedFileURL.path] + urls.map(\.absoluteString)
        )
        completion(.success(()))
      } catch {
        completion(.failure(.launchFailed(error.localizedDescription)))
      }
    }
  }
}
