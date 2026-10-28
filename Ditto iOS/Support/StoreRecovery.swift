//
//  StoreRecovery.swift
//  DittoiOS
//
//  Last-resort recovery when the local SwiftData store can't be opened. We move
//  the store files aside rather than deleting them, so the user's data is never
//  silently lost and can be recovered manually if needed.
//

import Foundation

enum StoreRecovery {
    /// Rename the existing store files with a timestamped `.corrupt-…` suffix.
    static func backupStore() {
        let support = SharedStore.directory
        let storeFiles = SharedStore.storeFiles

        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")

        for name in storeFiles {
            let source = support.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let destination = support.appendingPathComponent("\(name).corrupt-\(stamp)")
            try? FileManager.default.moveItem(at: source, to: destination)
        }
    }
}
