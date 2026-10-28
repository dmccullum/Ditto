//
//  SharedStore.swift
//  DittoiOS
//
//  Where the SwiftData store lives on disk. It sits in the App Group
//  container so the widget extension (Home and Lock Screen widgets, Control Center
//  controls) opens the same database as the app. Compiled into both the
//  app and the widget extension.
//

import Foundation

enum SharedStore {
    /// From the DITTO_APP_GROUP build setting via Info.plist: macOS uses the
    /// team-prefixed form its provisioning profiles allow, iOS a `group.` ID.
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "DittoAppGroup") as? String ?? ""

    /// The store plus the two SQLite sidecar files that travel with it.
    static let storeFiles = ["default.store", "default.store-shm", "default.store-wal"]

    /// Library/Application Support inside the App Group container, or the
    /// app's own Application Support when the group isn't available (a build
    /// signed without the App Groups entitlement).
    static var directory: URL {
        guard !appGroup.isEmpty, let group = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return legacyDirectory }
        return group.appending(path: "Library/Application Support", directoryHint: .isDirectory)
    }

    static var storeURL: URL { directory.appending(path: storeFiles[0]) }

    /// True once the app has created (or migrated) the store. The widget
    /// extension checks this so it never creates an empty store of its own,
    /// which would stop the app from migrating the user's existing library.
    static var storeExists: Bool {
        FileManager.default.fileExists(atPath: storeURL.path(percentEncoded: false))
    }

    /// Where versions before the widgets kept the store.
    private static var legacyDirectory: URL { URL.applicationSupportDirectory }

    /// Copy a store from before the App Group move into the group container.
    /// Runs once, before the container opens; the originals stay where they
    /// were as a backup. Each file is copied under a temporary name and then
    /// renamed, sidecars first, so an interrupted copy never leaves a partial
    /// `default.store` behind — the next launch simply tries again.
    static func migrateLegacyStoreIfNeeded() {
        let fileManager = FileManager.default
        let target = directory
        guard target.standardizedFileURL != legacyDirectory.standardizedFileURL,
              !storeExists,
              fileManager.fileExists(atPath: legacyDirectory.appending(path: storeFiles[0]).path(percentEncoded: false))
        else { return }

        do {
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            for name in storeFiles.reversed() {
                let source = legacyDirectory.appending(path: name)
                guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
                let staged = target.appending(path: name + ".migrating")
                let destination = target.appending(path: name)
                try? fileManager.removeItem(at: staged)
                try? fileManager.removeItem(at: destination)
                try fileManager.copyItem(at: source, to: staged)
                try fileManager.moveItem(at: staged, to: destination)
            }
        } catch {
            // Leave no half-copied sidecars next to a missing store.
            for name in storeFiles {
                try? fileManager.removeItem(at: target.appending(path: name))
                try? fileManager.removeItem(at: target.appending(path: name + ".migrating"))
            }
        }
    }
}
