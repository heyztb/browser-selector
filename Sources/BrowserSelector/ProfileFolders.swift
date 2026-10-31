// Copyright (c) 2026 Zach Blake
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A browser data folder that Browser Selector reads to list profiles.
struct ProfileFolder: Identifiable, Equatable, Sendable {
  let browserName: String
  let url: URL
  let bookmarkKey: String

  var id: String { bookmarkKey }
}

enum FolderAuthorization {
  static func save(_ url: URL, for folder: ProfileFolder) throws {
    let data: Data
    do {
      data = try url.bookmarkData(
        options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    } catch {
      // An unsandboxed build may not support security-scoped bookmarks. The
      // Open panel still grants access; retain a regular bookmark for the path.
      data = try url.bookmarkData(
        options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    UserDefaults.standard.set(data, forKey: folder.bookmarkKey)
  }

  static func startAccessing(_ folder: ProfileFolder) -> URL? {
    guard let data = UserDefaults.standard.data(forKey: folder.bookmarkKey) else { return nil }
    var stale = false
    let scopedURL = try? URL(
      resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil,
      bookmarkDataIsStale: &stale)
    let url = scopedURL ?? (try? URL(
      resolvingBookmarkData: data, options: [], relativeTo: nil,
      bookmarkDataIsStale: &stale))
    guard let url, url.standardizedFileURL == folder.url.standardizedFileURL else { return nil }
    return url.startAccessingSecurityScopedResource() ? url : nil
  }

  static func isPermissionError(_ error: Error) -> Bool {
    let error = error as NSError
    return (error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError)
      || (error.domain == NSPOSIXErrorDomain && (error.code == EACCES || error.code == EPERM))
  }
}
