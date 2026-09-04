import AppKit
import Combine
import Foundation

@MainActor
final class DefaultBrowserManager: ObservableObject {
  private static let verificationAttempts = 8
  private static let verificationDelay = Duration.milliseconds(250)

  @Published private(set) var isDefaultBrowser = false
  @Published private(set) var isChanging = false
  @Published var errorMessage: String?

  private let workspace: NSWorkspace
  private var changeErrors: [String] = []

  init(workspace: NSWorkspace = .shared) {
    self.workspace = workspace
    refresh()
  }

  func refresh() {
    isDefaultBrowser = ["http", "https"].allSatisfy(isCurrentAppDefault)
  }

  func setAsDefault() {
    guard !isChanging else { return }
    isChanging = true
    errorMessage = nil
    changeErrors = []
    setScheme(at: 0, schemes: ["http", "https"])
  }

  private func setScheme(at index: Int, schemes: [String]) {
    guard index < schemes.count else {
      verifyChange(attemptsRemaining: Self.verificationAttempts)
      return
    }

    workspace.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: schemes[index])
    { [weak self] error in
      Task { @MainActor in
        guard let self else { return }
        if let error {
          self.changeErrors.append("\(schemes[index]): \(error.localizedDescription)")
        }
        self.setScheme(at: index + 1, schemes: schemes)
      }
    }
  }

  private func verifyChange(attemptsRemaining: Int) {
    refresh()
    if isDefaultBrowser {
      isChanging = false
      errorMessage = nil
      return
    }

    guard attemptsRemaining > 0 else {
      isChanging = false
      errorMessage =
        changeErrors.first
        ?? "macOS did not make Browser Selector the default for both HTTP and HTTPS."
      return
    }

    Task { [weak self] in
      try? await Task.sleep(for: Self.verificationDelay)
      guard !Task.isCancelled else { return }
      self?.verifyChange(attemptsRemaining: attemptsRemaining - 1)
    }
  }

  private func isCurrentAppDefault(_ scheme: String) -> Bool {
    guard let url = URL(string: "\(scheme)://example.invalid"),
      let handlerURL = workspace.urlForApplication(toOpen: url)
    else { return false }

    if let expectedID = Bundle.main.bundleIdentifier,
      let actualID = Bundle(url: handlerURL)?.bundleIdentifier
    {
      return expectedID.caseInsensitiveCompare(actualID) == .orderedSame
    }
    return handlerURL.resolvingSymlinksInPath() == Bundle.main.bundleURL.resolvingSymlinksInPath()
  }

  func openSystemSettings() {
    let candidates = [
      "x-apple.systempreferences:com.apple.Desktop-Settings.extension?DefaultWebBrowser",
      "x-apple.systempreferences:com.apple.preference.general?DefaultWebBrowser",
    ]
    for candidate in candidates {
      if let url = URL(string: candidate), workspace.open(url) { return }
    }
  }
}
