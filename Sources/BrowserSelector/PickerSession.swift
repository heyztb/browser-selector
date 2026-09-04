import Combine
import Foundation

@MainActor
final class PickerSession: ObservableObject {
  struct Selection: Equatable, Sendable {
    let urls: [URL]
    let target: BrowserTarget
  }

  @Published private(set) var pendingURLs: [URL]
  @Published private(set) var targets: [BrowserTarget]
  @Published var focusedIndex: Int
  @Published private(set) var errorMessage: String?
  @Published private(set) var isLaunching = false

  private(set) var hasCompleted = false

  init(urls: [URL], targets: [BrowserTarget]) {
    self.pendingURLs = Self.accepted(urls)
    self.targets = targets
    self.focusedIndex = 0
  }

  var destinationLabel: String {
    guard pendingURLs.count == 1 else { return "\(pendingURLs.count) links" }
    let url = pendingURLs[0]
    if url.isFileURL { return url.lastPathComponent }
    return url.host(percentEncoded: false) ?? url.absoluteString
  }

  func append(urls: [URL]) {
    guard !hasCompleted else { return }
    pendingURLs.append(contentsOf: Self.accepted(urls))
  }

  func moveFocus(by delta: Int) {
    guard !targets.isEmpty, !isLaunching else { return }
    focusedIndex = (focusedIndex + delta % targets.count + targets.count) % targets.count
  }

  func focus(_ index: Int) {
    guard targets.indices.contains(index), !isLaunching else { return }
    focusedIndex = index
  }

  func selectFocused() -> Selection? {
    select(index: focusedIndex)
  }

  func select(index: Int) -> Selection? {
    guard !hasCompleted, !isLaunching,
      targets.indices.contains(index),
      !pendingURLs.isEmpty
    else { return nil }
    isLaunching = true
    errorMessage = nil
    return Selection(urls: pendingURLs, target: targets[index])
  }

  func finish(_ result: Result<Void, BrowserLaunchError>) {
    guard isLaunching else { return }
    switch result {
    case .success:
      hasCompleted = true
      isLaunching = false
    case .failure(let error):
      isLaunching = false
      errorMessage = error.localizedDescription
    }
  }

  func cancel() -> Bool {
    guard !isLaunching, !hasCompleted else { return false }
    hasCompleted = true
    return true
  }

  private static func accepted(_ urls: [URL]) -> [URL] {
    urls.filter { url in
      guard let scheme = url.scheme?.lowercased() else { return false }
      return scheme == "http" || scheme == "https" || scheme == "file"
    }
  }
}
