//
//  DittoStore.swift
//  DittoiOS
//
//  Owns the shared ModelContainer so every entry point — the app UI and
//  App Intents (Siri, Shortcuts, Spotlight) — talks to the same store.
//

import SwiftData
import Foundation

@MainActor
enum DittoStore {
    /// Try CloudKit first; fall back to local store if iCloud isn't available
    /// (e.g. free Personal Team without the CloudKit entitlement).
    static let container: ModelContainer = {
        let schema = Schema([Snippet.self, Category.self])
        #if DEBUG
        if DemoLibrary.isEnabled { return DemoLibrary.makeContainer(schema: schema) }
        #endif
        let cloudConfig = ModelConfiguration(cloudKitDatabase: .automatic)
        let localConfig = ModelConfiguration()
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: cloudConfig)
        } catch {
            do {
                container = try ModelContainer(for: schema, configurations: localConfig)
            } catch {
                // Last resort: the local store can't be opened. Move it aside —
                // never delete — so the data stays recoverable, then start fresh.
                StoreRecovery.backupStore()
                container = try! ModelContainer(for: schema, configurations: localConfig)
            }
        }
        SampleData.seedIfNeeded(container.mainContext)
        backfillUUIDs(container.mainContext)
        return container
    }()

    /// True when running the in-memory demo library (`-DittoDemo`, Debug only).
    /// Used to keep demo content out of Spotlight and Shortcuts.
    static var isDemo: Bool {
        #if DEBUG
        DemoLibrary.isEnabled
        #else
        false
        #endif
    }

    /// Give every pre-existing row a stable UUID (new rows get one in init).
    /// App Intents and Spotlight use these to identify items across launches.
    private static func backfillUUIDs(_ context: ModelContext) {
        var dirty = false
        for snippet in (try? context.fetch(FetchDescriptor<Snippet>())) ?? [] where snippet.uuid == nil {
            snippet.uuid = UUID()
            dirty = true
        }
        for category in (try? context.fetch(FetchDescriptor<Category>())) ?? [] where category.uuid == nil {
            category.uuid = UUID()
            dirty = true
        }
        if dirty { try? context.save() }
    }
}
