// Copyright (c) 2026 Zach Blake
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import Foundation

@MainActor
final class TargetStore: ObservableObject {
  @Published private(set) var targets: [BrowserTarget] = []
  @Published private(set) var warnings: [String] = []
  @Published private(set) var foldersNeedingAccess: [ProfileFolder] = []
  @Published private(set) var folderAccessError: String?
  @Published private(set) var staysOpenInBackground: Bool

  private let discovery: BrowserDiscovering
  private let defaults: UserDefaults
  private let preferencesKey = "targetPreferences.v1"
  private let backgroundKey = "staysOpenInBackground.v1"

  init(discovery: BrowserDiscovering, defaults: UserDefaults = .standard) {
    self.discovery = discovery
    self.defaults = defaults
    self.staysOpenInBackground = defaults.bool(forKey: backgroundKey)
    refresh()
  }

  func setStaysOpenInBackground(_ enabled: Bool) {
    staysOpenInBackground = enabled
    defaults.set(enabled, forKey: backgroundKey)
  }

  var visibleTargets: [BrowserTarget] {
    targets.filter(\.isVisible).sorted { $0.order < $1.order }
  }

  func refresh() {
    let result = discovery.discover()
    targets = TargetReconciler.reconcile(
      discovered: result.targets,
      preferences: loadPreferences()
    )
    warnings = result.warnings
    foldersNeedingAccess = result.foldersNeedingAccess
    save()
  }

  func chooseFolder(_ folder: ProfileFolder) {
    let expected = folder.url.standardizedFileURL
    let displayPath = NSString(string: expected.path).abbreviatingWithTildeInPath
    let panel = NSOpenPanel()
    panel.message =
      "Approve access to this \(folder.browserName) folder to show its profiles in Browser Selector."
    panel.prompt = "Allow Access"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = expected
    guard panel.runModal() == .OK, let selected = panel.url else { return }
    guard selected.standardizedFileURL == expected else {
      folderAccessError = "Select the \(folder.browserName) folder at \(displayPath)."
      return
    }
    do {
      try FolderAuthorization.save(selected, for: folder)
    } catch {
      folderAccessError =
        "Could not save access to the \(folder.browserName) folder: \(error.localizedDescription)"
      return
    }
    folderAccessError = nil
    refresh()
    if foldersNeedingAccess.contains(folder) {
      folderAccessError = "macOS still denied access. Check Browser Selector in Privacy & Security settings."
    }
  }

  func setVisible(_ visible: Bool, for id: String) {
    guard let index = targets.firstIndex(where: { $0.id == id }) else { return }
    if !visible, targets[index].isVisible, visibleTargets.count == 1 {
      NSSound.beep()
      return
    }
    targets[index].isVisible = visible
    save()
  }

  func setCustomName(_ name: String, for id: String) {
    guard let index = targets.firstIndex(where: { $0.id == id }) else { return }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    targets[index].customName = trimmed.isEmpty ? nil : trimmed
    save()
  }

  func resetName(for id: String) {
    guard let index = targets.firstIndex(where: { $0.id == id }) else { return }
    targets[index].customName = nil
    save()
  }

  /// Moves `id` into `destinationID`'s position, shifting the rows in between.
  func moveTarget(id: String, to destinationID: String) {
    guard
      let source = targets.firstIndex(where: { $0.id == id }),
      let destination = targets.firstIndex(where: { $0.id == destinationID }),
      source != destination
    else { return }
    targets.insert(targets.remove(at: source), at: destination)
    normalizeOrderAndSave()
  }

  func moveTarget(id: String, direction: Int) {
    guard let index = targets.firstIndex(where: { $0.id == id }) else { return }
    let destination = index + direction
    guard targets.indices.contains(destination) else { return }
    targets.swapAt(index, destination)
    normalizeOrderAndSave()
  }

  private func normalizeOrderAndSave() {
    for index in targets.indices {
      targets[index].order = index
    }
    save()
  }

  private func loadPreferences() -> [String: TargetPreferences] {
    guard let data = defaults.data(forKey: preferencesKey),
      let preferences = try? JSONDecoder().decode([String: TargetPreferences].self, from: data)
    else { return [:] }
    return preferences
  }

  private func save() {
    var preferences = loadPreferences()
    preferences.merge(TargetReconciler.preferences(from: targets)) { _, current in current }
    guard let data = try? JSONEncoder().encode(preferences) else { return }
    defaults.set(data, forKey: preferencesKey)
  }
}
