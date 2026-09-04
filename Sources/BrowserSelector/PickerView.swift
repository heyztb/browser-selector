import AppKit
import SwiftUI

struct PickerView: View {
  @ObservedObject var session: PickerSession
  let onSelect: (Int) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 7) {
        Image(systemName: session.pendingURLs.count == 1 ? "link" : "link.badge.plus")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        Text(session.destinationLabel)
          .font(.headline)
          .lineLimit(1)
          .truncationMode(.middle)
          .accessibilityLabel("Destination: \(session.destinationLabel)")
        Spacer(minLength: 0)
        if session.isLaunching {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel("Opening browser")
        }
      }
      .padding(.horizontal, 12)
      .padding(.top, 11)

      VStack(spacing: 3) {
        ForEach(Array(session.targets.enumerated()), id: \.element.id) { index, target in
          Button {
            onSelect(index)
          } label: {
            HStack(spacing: 10) {
              Text(index < 9 ? "\(index + 1)" : "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 13, alignment: .trailing)
                .accessibilityHidden(true)
              BrowserIcon(appURL: target.appURL)
              Text(target.displayName)
                .lineLimit(1)
                .truncationMode(.tail)
              Spacer(minLength: 8)
              if session.focusedIndex == index {
                Image(systemName: "return")
                  .font(.caption)
                  .foregroundStyle(.tertiary)
                  .accessibilityHidden(true)
              }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 9)
            .frame(height: 38)
            .background(
              RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(session.focusedIndex == index ? Color.accentColor.opacity(0.18) : .clear)
            )
          }
          .buttonStyle(.plain)
          .disabled(session.isLaunching)
          .onHover { hovering in
            if hovering { session.focus(index) }
          }
          .accessibilityIdentifier("browser-target-\(index)")
          .accessibilityLabel(
            index < 9 ? "\(target.displayName), shortcut \(index + 1)" : target.displayName)
        }
      }
      .padding(.horizontal, 5)

      if let error = session.errorMessage {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 12)
          .padding(.bottom, 4)
          .accessibilityIdentifier("launch-error")
      }
    }
    .padding(.bottom, 6)
    .frame(width: 330)
    .background(.regularMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(.separator.opacity(0.55), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    .accessibilityIdentifier("browser-picker")
  }
}

private struct BrowserIcon: View {
  let appURL: URL

  var body: some View {
    Image(nsImage: icon)
      .resizable()
      .interpolation(.high)
      .frame(width: 24, height: 24)
      .accessibilityHidden(true)
  }

  private var icon: NSImage {
    let image = NSWorkspace.shared.icon(forFile: appURL.path)
    image.size = NSSize(width: 48, height: 48)
    return image
  }
}
