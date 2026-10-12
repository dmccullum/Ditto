//
//  StoreRecovery.swift
//  Ditto
//
//  Last-resort recovery when the local SwiftData store can't be opened. We move
//  the store files aside rather than deleting them, so the user's data is never
//  silently lost and can be recovered manually if needed.
//

import Foundation

enum StoreRecovery {
    private static let storeFiles = ["default.store", "default.store-shm", "default.store-wal"]

    /// Rename the existing store files with a timestamped `.corrupt-…` suffix.
    static func backupStore() {
        guard let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }

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
