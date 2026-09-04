import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
  var onClose: (() -> Void)?

  init(store: TargetStore, defaultBrowser: DefaultBrowserManager) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Browser Selector Settings"
    window.minSize = NSSize(width: 620, height: 440)
    window.isReleasedWhenClosed = false
    window.center()
    window.contentViewController = NSHostingController(
      rootView: SettingsView(store: store, defaultBrowser: defaultBrowser)
    )
    super.init(window: window)
    window.delegate = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func show() {
    NSApp.activate()
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    onClose?()
  }
}
