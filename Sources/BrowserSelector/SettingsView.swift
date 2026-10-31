// Copyright (c) 2026 Zach Blake
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

struct SettingsView: View {
  @ObservedObject var store: TargetStore
  @ObservedObject var defaultBrowser: DefaultBrowserManager
  let onBackgroundModeChanged: () -> Void
  let onQuit: () -> Void
  @State private var rowFrames: [String: CGRect] = [:]
  @State private var rowDrag: RowDrag?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .center, spacing: 12) {
        Image(
          systemName: defaultBrowser.isDefaultBrowser ? "checkmark.circle.fill" : "circle.dashed"
        )
        .font(.title2)
        .foregroundStyle(defaultBrowser.isDefaultBrowser ? .green : .secondary)
        .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(defaultBrowser.isDefaultBrowser ? "Default browser" : "Not the default browser")
            .font(.headline)
          Text("Browser Selector handles HTTP and HTTPS links.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if !defaultBrowser.isDefaultBrowser {
          Button("Set as Default Browser") {
            defaultBrowser.setAsDefault()
          }
          .disabled(defaultBrowser.isChanging)
          .accessibilityIdentifier("set-default-browser")
        }
      }

      if let error = defaultBrowser.errorMessage {
        HStack(alignment: .firstTextBaseline) {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
          Spacer()
          Button("Open System Settings") { defaultBrowser.openSystemSettings() }
        }
        .font(.caption)
      }

      Divider()

      ForEach(store.foldersNeedingAccess) { folder in
        HStack(alignment: .center, spacing: 12) {
          VStack(alignment: .leading, spacing: 2) {
            Text("\(folder.browserName) profiles need access")
              .font(.headline)
            Text(
              "macOS denied access. Approve the \(folder.browserName) folder in the chooser to show individual profiles."
            )
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button("Grant \(folder.browserName) Access") { store.chooseFolder(folder) }
            .accessibilityIdentifier("choose-profile-folder")
        }
      }
      if let error = store.folderAccessError {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.red)
      }

      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Browsers")
            .font(.headline)
          Text("Enable, rename, and drag to order the choices shown for each link.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          store.refresh()
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .accessibilityIdentifier("refresh-browsers")
      }

      // Rows are reordered by dragging their handle; the row itself lifts and
      // follows the pointer. This is a ScrollView rather than a List because
      // List clips each row to its cell, and List's .onMove makes the whole row
      // a drag source, which swallows clicks intended for the name fields.
      ScrollView {
        VStack(spacing: 0) {
          ForEach(Array(store.targets.enumerated()), id: \.element.id) { index, target in
            TargetSettingsRow(
              target: target,
              canDisable: !target.isVisible || store.visibleTargets.count > 1,
              canMoveUp: index > 0,
              canMoveDown: index + 1 < store.targets.count,
              isDragging: rowDrag?.id == target.id,
              onVisibilityChanged: { store.setVisible($0, for: target.id) },
              onNameChanged: { store.setCustomName($0, for: target.id) },
              onResetName: { store.resetName(for: target.id) },
              onMoveUp: { store.moveTarget(id: target.id, direction: -1) },
              onMoveDown: { store.moveTarget(id: target.id, direction: 1) },
              onDragChanged: { dragRow(target.id, from: index, by: $0) },
              onDragEnded: endRowDrag
            )
            .offset(y: rowOffset(for: target.id, at: index))
            .background {
              GeometryReader { proxy in
                Color.clear.preference(
                  key: RowFramesKey.self,
                  value: [target.id: proxy.frame(in: .named(rowCoordinateSpace))]
                )
              }
            }
            .zIndex(rowDrag?.id == target.id ? 1 : 0)
          }
        }
        .padding(6)
        .coordinateSpace(name: rowCoordinateSpace)
        .onPreferenceChange(RowFramesKey.self) { frames in
          MainActor.assumeIsolated { rowFrames = frames }
        }
      }
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
      .frame(minHeight: 260)
      .accessibilityIdentifier("browser-list")

      if !store.warnings.isEmpty {
        DisclosureGroup("Discovery notices") {
          ForEach(store.warnings, id: \.self) { warning in
            Text(warning).font(.caption).foregroundStyle(.secondary)
          }
        }
        .font(.caption)
      }

      Divider()
      HStack {
        Toggle(
          "Keep Browser Selector running between links",
          isOn: Binding(
            get: { store.staysOpenInBackground },
            set: {
              store.setStaysOpenInBackground($0)
              onBackgroundModeChanged()
            }
          )
        )
        .accessibilityIdentifier("keep-running-between-links")
        Spacer()
        Button("Quit Browser Selector", action: onQuit)
          .accessibilityIdentifier("quit-browser-selector")
      }
      Text(
        store.staysOpenInBackground
          ? "Browser Selector stays in the menu bar after you close this window. Click its globe icon to open Settings or quit."
          : "When enabled, Browser Selector stays ready for the next link and adds a menu bar icon for Settings and Quit."
      )
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(20)
    .frame(minWidth: 620, idealWidth: 680, minHeight: 440)
    .onAppear { defaultBrowser.refresh() }
  }

  private func dragRow(_ id: String, from sourceIndex: Int, by translation: CGFloat) {
    if rowDrag?.id != id {
      rowDrag = RowDrag(id: id, sourceIndex: sourceIndex, translation: 0, destinationIndex: sourceIndex)
    }
    rowDrag?.translation = translation
    let destination = destinationIndex(for: id, translation: translation)
    if destination != rowDrag?.destinationIndex {
      withAnimation(.easeInOut(duration: 0.15)) { rowDrag?.destinationIndex = destination }
    }
  }

  private func endRowDrag() {
    guard let drag = rowDrag else { return }
    withAnimation(.easeInOut(duration: 0.15)) {
      if drag.destinationIndex != drag.sourceIndex, store.targets.indices.contains(drag.destinationIndex) {
        store.moveTarget(id: drag.id, to: store.targets[drag.destinationIndex].id)
      }
      rowDrag = nil
    }
  }

  /// The slot under the dragged row's center, measured against the resting layout.
  private func destinationIndex(for id: String, translation: CGFloat) -> Int {
    guard let frame = rowFrames[id] else { return rowDrag?.sourceIndex ?? 0 }
    let center = frame.midY + translation
    let slot = store.targets.firstIndex { (rowFrames[$0.id]?.maxY ?? .infinity) > center }
    return slot ?? store.targets.count - 1
  }

  /// The dragged row follows the pointer; rows between its source and
  /// destination slide over by one row to open a gap.
  private func rowOffset(for id: String, at index: Int) -> CGFloat {
    guard let drag = rowDrag else { return 0 }
    if id == drag.id { return drag.translation }
    let height = rowFrames[drag.id]?.height ?? 0
    if drag.sourceIndex < index, index <= drag.destinationIndex { return -height }
    if drag.destinationIndex <= index, index < drag.sourceIndex { return height }
    return 0
  }
}

private let rowCoordinateSpace = "browser-rows"

private struct RowDrag {
  let id: String
  let sourceIndex: Int
  var translation: CGFloat
  var destinationIndex: Int
}

private struct RowFramesKey: PreferenceKey {
  static let defaultValue: [String: CGRect] = [:]

  static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
    value.merge(nextValue()) { $1 }
  }
}

private struct TargetSettingsRow: View {
  let target: BrowserTarget
  let canDisable: Bool
  let canMoveUp: Bool
  let canMoveDown: Bool
  let isDragging: Bool
  let onVisibilityChanged: (Bool) -> Void
  let onNameChanged: (String) -> Void
  let onResetName: () -> Void
  let onMoveUp: () -> Void
  let onMoveDown: () -> Void
  let onDragChanged: (CGFloat) -> Void
  let onDragEnded: () -> Void
  /// Resets when the gesture ends or is cancelled, so a cancelled drag still settles.
  @GestureState private var isDragGestureActive = false

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "line.3.horizontal")
        .foregroundStyle(.secondary)
        .frame(width: 16, height: 28)
        .contentShape(Rectangle())
        .onHover { inside in inside ? NSCursor.openHand.push() : NSCursor.pop() }
        .gesture(
          // Measured in the stable list space so the row's own offset doesn't feed back.
          DragGesture(minimumDistance: 2, coordinateSpace: .named(rowCoordinateSpace))
            .updating($isDragGestureActive) { _, active, _ in active = true }
            .onChanged { onDragChanged($0.translation.height) }
            .onEnded { _ in onDragEnded() }
        )
        .onChange(of: isDragGestureActive) { _, active in
          if !active { onDragEnded() }
        }
        .help("Drag to reorder")
        .accessibilityHidden(true)

      Toggle(
        "",
        isOn: Binding(
          get: { target.isVisible },
          set: { newValue in onVisibilityChanged(newValue) }
        )
      )
      .labelsHidden()
      .disabled(!canDisable)
      .accessibilityLabel("Show \(target.displayName)")

      Image(nsImage: NSWorkspace.shared.icon(forFile: target.appURL.path))
        .resizable()
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        TextField(
          target.discoveredName,
          text: Binding(
            get: { target.customName ?? "" },
            set: { newValue in onNameChanged(newValue) }
          )
        )
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel("Display name for \(target.discoveredName)")

        Text(detail)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Button {
        onResetName()
      } label: {
        Image(systemName: "arrow.uturn.backward")
      }
      .buttonStyle(.borderless)
      .disabled(target.customName == nil)
      .help("Reset name")
      .accessibilityLabel("Reset name for \(target.displayName)")

      VStack(spacing: 1) {
        Button(action: onMoveUp) { Image(systemName: "chevron.up") }
          .disabled(!canMoveUp)
          .accessibilityLabel("Move \(target.displayName) up")
        Button(action: onMoveDown) { Image(systemName: "chevron.down") }
          .disabled(!canMoveDown)
          .accessibilityLabel("Move \(target.displayName) down")
      }
      .buttonStyle(.borderless)
    }
    .padding(.vertical, 6)
    .padding(.horizontal, 8)
    .background {
      // Lifted card for the row being dragged. No scale effect: on a wide
      // window even a 2% scale visibly shifts the row's edges sideways.
      if isDragging {
        RoundedRectangle(cornerRadius: 6)
          .fill(Color(nsColor: .controlBackgroundColor))
          .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
          .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
      }
    }
    .animation(.easeInOut(duration: 0.12), value: isDragging)
  }

  private var detail: String {
    switch target.kind {
    case .application:
      target.appURL.path
    case .firefoxProfile(let path):
      "Firefox profile · \(path.path)"
    case .chromiumProfile(let userDataDirectory, let directory):
      "Chromium profile · \(userDataDirectory.appendingPathComponent(directory).path)"
    }
  }
}
