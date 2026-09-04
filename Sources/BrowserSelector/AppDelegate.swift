import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let store: TargetStore
  private let launcher: BrowserLaunching
  private let defaultBrowser: DefaultBrowserManager
  private var settingsController: SettingsWindowController?
  private var pickerController: PickerWindowController?
  private var receivedURLs = false
  private var deferredURLs: [URL] = []

  override init() {
    let discovery = BrowserDiscovery()
    self.store = TargetStore(discovery: discovery)
    self.launcher = BrowserLauncher()
    self.defaultBrowser = DefaultBrowserManager()
    super.init()
  }

  func applicationWillFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
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
    if !flag, pickerController == nil { showSettings() }
    return true
  }

  private func showSettings() {
    if settingsController == nil {
      let controller = SettingsWindowController(store: store, defaultBrowser: defaultBrowser)
      controller.onClose = { [weak self] in
        guard let self, self.pickerController == nil else { return }
        NSApp.terminate(nil)
      }
      settingsController = controller
    }
    store.refresh()
    defaultBrowser.refresh()
    settingsController?.show()
  }

  private func showPicker(urls: [URL]) {
    store.refresh()
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
            NSApp.terminate(nil)
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
      NSApp.terminate(nil)
    }
    pickerController = controller

    settingsController?.onClose = nil
    settingsController?.close()
    settingsController = nil
    controller.show()
  }
}
