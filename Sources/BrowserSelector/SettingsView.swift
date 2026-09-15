import AppKit
import SwiftUI

struct SettingsView: View {
  @ObservedObject var store: TargetStore
  @ObservedObject var defaultBrowser: DefaultBrowserManager

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

      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Browsers")
            .font(.headline)
          Text("Enable, rename, and order the choices shown for each link.")
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

      List {
        ForEach(Array(store.targets.enumerated()), id: \.element.id) { index, target in
          TargetSettingsRow(
            target: target,
            canDisable: !target.isVisible || store.visibleTargets.count > 1,
            canMoveUp: index > 0,
            canMoveDown: index + 1 < store.targets.count,
            onVisibilityChanged: { store.setVisible($0, for: target.id) },
            onNameChanged: { store.setCustomName($0, for: target.id) },
            onResetName: { store.resetName(for: target.id) },
            onMoveUp: { store.moveTarget(id: target.id, direction: -1) },
            onMoveDown: { store.moveTarget(id: target.id, direction: 1) }
          )
        }
        // Use the row's arrow buttons for reordering. List's drag-to-move
        // handling intercepts clicks intended for the editable name fields.
      }
      .listStyle(.inset)
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
    }
    .padding(20)
    .frame(minWidth: 620, idealWidth: 680, minHeight: 440)
    .onAppear { defaultBrowser.refresh() }
  }
}

private struct TargetSettingsRow: View {
  let target: BrowserTarget
  let canDisable: Bool
  let canMoveUp: Bool
  let canMoveDown: Bool
  let onVisibilityChanged: (Bool) -> Void
  let onNameChanged: (String) -> Void
  let onResetName: () -> Void
  let onMoveUp: () -> Void
  let onMoveDown: () -> Void

  var body: some View {
    HStack(spacing: 10) {
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
    .padding(.vertical, 3)
  }

  private var detail: String {
    if let path = target.profilePath {
      return "Firefox profile · \(path.path)"
    }
    return target.appURL.path
  }
}
