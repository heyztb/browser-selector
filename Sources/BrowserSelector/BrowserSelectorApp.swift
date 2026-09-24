// Copyright (c) 2026 Zach Blake
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

@main
@MainActor
enum BrowserSelectorApp {
  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
    withExtendedLifetime(delegate) {}
  }
}
