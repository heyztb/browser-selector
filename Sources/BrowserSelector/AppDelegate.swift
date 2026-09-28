// Copyright (c) 2026 Zach Blake
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let store: TargetStore
  private let launcher: BrowserLaunching
  private let defaultBrowser: DefaultBrowserManager
  private var settingsController: SettingsWindowController?
  private var pickerController: PickerWindowController?
  private var statusItem: NSStatusItem?
  private var receivedURLs = false
  private var deferredURLs: [URL] = []
  private var needsPickerRefresh = false

  override init() {
    let discovery = BrowserDiscovery()
    self.store = TargetStore(discovery: discovery)
    self.launcher = BrowserLauncher()
    self.defaultBrowser = DefaultBrowserManager()
    super.init()
    updateStatusItem()
  }

  func applicationWillFinishLaunching(_ notification: Notification) {
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
      forEventClass: AEEventClass(kInternetEventClass),
      andEventID: AEEventID(kAEGetURL)
    )
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Launch Services may deliver application(_:open:) just after this callback.
    // Delay the direct-launch Settings window long enough to distinguish the two paths.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
      guard let self, !self.receivedURLs, self.pickerController == nil else { return }
      guard !self.store.staysOpenInBackground else { return }
      self.showSettings()
    }
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    handleIncomingURLs(urls)
  }

  @objc private func handleGetURLEvent(
    _ event: NSAppleEventDescriptor,
    withReplyEvent replyEvent: NSAppleEventDescriptor
  ) {
    guard
      let value = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
      let url = URL(string: value)
    else { return }
    handleIncomingURLs([url])
  }

  private func handleIncomingURLs(_ urls: [URL]) {
    let accepted = urls.filter {
      guard let scheme = $0.scheme?.lowercased() else { return false }
      return scheme == "http" || scheme == "https" || scheme == "file"
    }
    guard !accepted.isEmpty else { return }
    receivedURLs = true

    if let pickerController {
      if pickerController.session.isLaunching {
        deferredURLs.append(contentsOf: accepted)
      } else {
        pickerController.append(urls: accepted)
      }
      return
    }
    showPicker(urls: accepted)
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    // Launch Services can send a reopen event alongside a URL to a running app.
    // In resident mode, Settings is available from the menu bar instead.
    if pickerController == nil, !store.staysOpenInBackground { showSettings() }
    return false
  }

  private func showSettings() {
    // Settings is a normal app window so launchers and window managers can surface it.
    // This also restores regular behavior if Settings replaces an accessory picker.
    NSApp.setActivationPolicy(.regular)
    if settingsController == nil {
      let controller = SettingsWindowController(
        store: store, defaultBrowser: defaultBrowser,
        onBackgroundModeChanged: { [weak self] in self?.updateStatusItem() },
        onQuit: { NSApp.terminate(nil) })
      controller.onClose = { [weak self] in
        self?.settingsClosed()
      }
      settingsController = controller
    }
    store.refresh()
    needsPickerRefresh = true
    defaultBrowser.refresh()
    settingsController?.show()
  }

  private func showPicker(urls: [URL]) {
    // TargetStore discovers browsers during initialization. A second scan on the
    // cold link path delays the picker without providing newer data.
    if needsPickerRefresh {
      store.refresh()
      needsPickerRefresh = false
    }
    let targets = store.visibleTargets
    guard !targets.isEmpty else {
      showSettings()
      let alert = NSAlert()
      alert.messageText = "No browsers are enabled"
      alert.informativeText = "Enable at least one detected browser before opening a link."
      alert.alertStyle = .warning
      if let window = settingsController?.window {
        alert.beginSheetModal(for: window)
      }
      return
    }

    NSApp.setActivationPolicy(.accessory)

    let session = PickerSession(urls: urls, targets: targets)
    let controller = PickerWindowController(session: session)
    controller.onSelection = { [weak self, weak controller] selection in
      guard let self, let controller else { return }
      self.launcher.open(urls: selection.urls, with: selection.target) {
        [weak self, weak controller] result in
        guard let self, let controller else { return }
        controller.selectionFinished(result)
        switch result {
        case .success:
          controller.window?.orderOut(nil)
          self.pickerController = nil
          if self.deferredURLs.isEmpty {
            self.finishPicker()
          } else {
            let queued = self.deferredURLs
            self.deferredURLs.removeAll()
            self.showPicker(urls: queued)
          }
        case .failure:
          break
        }
      }
    }
    controller.onCancel = { [weak self] in
      self?.pickerController = nil
      self?.deferredURLs.removeAll()
      self?.finishPicker()
    }
    pickerController = controller

    settingsController?.onClose = nil
    settingsController?.close()
    settingsController = nil
    controller.show()
  }

  private func settingsClosed() {
    guard pickerController == nil else { return }
    if store.staysOpenInBackground {
      NSApp.setActivationPolicy(.accessory)
    } else {
      NSApp.terminate(nil)
    }
  }

  private func finishPicker() {
    if !store.staysOpenInBackground {
      NSApp.terminate(nil)
    }
  }

  private func updateStatusItem() {
    guard store.staysOpenInBackground else {
      if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
      statusItem = nil
      return
    }
    guard statusItem == nil else { return }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Browser Selector")
    let menu = NSMenu()
    menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ""))
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Quit Browser Selector", action: #selector(quitFromMenu), keyEquivalent: ""))
    for menuItem in menu.items where menuItem.action != nil { menuItem.target = self }
    item.menu = menu
    statusItem = item
  }

  @objc private func openSettingsFromMenu() { showSettings() }

  @objc private func quitFromMenu() { NSApp.terminate(nil) }
}
