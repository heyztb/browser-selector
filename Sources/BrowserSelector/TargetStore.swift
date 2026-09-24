// Copyright (c) 2026 Zach Blake
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import Foundation

@MainActor
final class TargetStore: ObservableObject {
  @Published private(set) var targets: [BrowserTarget] = []
  @Published private(set) var warnings: [String] = []

  private let discovery: BrowserDiscovering
  private let defaults: UserDefaults
  private let preferencesKey = "targetPreferences.v1"

  init(discovery: BrowserDiscovering, defaults: UserDefaults = .standard) {
    self.discovery = discovery
    self.defaults = defaults
    refresh()
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
    save()
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

  func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
    targets.move(fromOffsets: offsets, toOffset: destination)
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
