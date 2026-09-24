// Copyright (c) 2026 Zach Blake
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

@MainActor
final class PickerPanel: NSPanel {
  var eventHandler: ((NSEvent) -> Bool)?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func keyDown(with event: NSEvent) {
    if eventHandler?(event) == true { return }
    super.keyDown(with: event)
  }
}

@MainActor
final class PickerWindowController: NSWindowController, NSWindowDelegate {
  let session: PickerSession
  var onSelection: ((PickerSession.Selection) -> Void)?
  var onCancel: (() -> Void)?
  private var dismissesOnResignKey = false

  init(session: PickerSession) {
    self.session = session
    let panel = PickerPanel(
      contentRect: .zero,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    super.init(window: panel)

    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
    panel.isMovableByWindowBackground = false
    panel.delegate = self
    panel.contentViewController = NSHostingController(
      rootView: PickerView(session: session) { _ in })
    panel.eventHandler = { [weak self] event in self?.handle(event) ?? false }
    replaceRootView()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func append(urls: [URL]) {
    session.append(urls: urls)
    resizeAndPosition()
  }

  func show() {
    guard !session.targets.isEmpty, !session.pendingURLs.isEmpty else {
      onCancel?()
      return
    }
    replaceRootView()
    resizeAndPosition()
    presentPanel()
  }

  func selectionFinished(_ result: Result<Void, BrowserLaunchError>) {
    session.finish(result)
    if case .failure = result {
      replaceRootView()
      resizeAndPosition()
      presentPanel()
    }
  }

  func windowDidResignKey(_ notification: Notification) {
    guard dismissesOnResignKey else { return }
    cancelIfPossible()
  }

  private func replaceRootView() {
    guard let host = window?.contentViewController as? NSHostingController<PickerView> else {
      return
    }
    host.rootView = PickerView(session: session) { [weak self] index in self?.select(index: index) }
  }

  private func select(index: Int) {
    guard let selection = session.select(index: index) else { return }
    onSelection?(selection)
  }

  private func cancelIfPossible() {
    guard session.cancel() else { return }
    window?.orderOut(nil)
    onCancel?()
  }

  private func handle(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown else { return false }
    switch event.keyCode {
    case 53:
      cancelIfPossible()
      return true
    case 36, 76:
      if let selection = session.selectFocused() { onSelection?(selection) }
      return true
    case 125:
      session.moveFocus(by: 1)
      return true
    case 126:
      session.moveFocus(by: -1)
      return true
    case 48:
      session.moveFocus(by: event.modifierFlags.contains(.shift) ? -1 : 1)
      return true
    default:
      if let character = event.charactersIgnoringModifiers?.first,
        let number = character.wholeNumberValue,
        (1...9).contains(number),
        let selection = session.select(index: number - 1)
      {
        onSelection?(selection)
        return true
      }
      return false
    }
  }

  private func presentPanel() {
    dismissesOnResignKey = false
    // A URL can arrive while another application is still active. The cooperative
    // `activate()` API is allowed to leave that application active, which makes the
    // visible picker miss its first key press. This transient chooser explicitly
    // takes focus because keyboard selection is its primary interaction.
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
    DispatchQueue.main.async { [weak self] in
      guard let self, self.window?.isVisible == true, !self.session.hasCompleted else { return }
      self.window?.makeKey()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      guard let self, self.window?.isVisible == true, !self.session.hasCompleted else { return }
      self.dismissesOnResignKey = true
    }
  }

  private func resizeAndPosition() {
    guard let window, let contentView = window.contentView else { return }
    contentView.layoutSubtreeIfNeeded()
    let fittingSize = contentView.fittingSize
    let size = NSSize(width: max(330, fittingSize.width), height: max(80, fittingSize.height))

    let mouse = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
    guard let visibleFrame = screen?.visibleFrame else { return }
    var origin = NSPoint(x: mouse.x + 12, y: mouse.y - size.height - 12)
    origin.x = min(max(origin.x, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)
    origin.y = min(max(origin.y, visibleFrame.minY + 8), visibleFrame.maxY - size.height - 8)
    window.setFrame(NSRect(origin: origin, size: size), display: true)
  }
}
