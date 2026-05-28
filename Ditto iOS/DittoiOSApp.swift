import SwiftUI
import SwiftData

@main
struct DittoiOSApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([Snippet.self, Category.self])
        // Try CloudKit first; fall back to local store if iCloud isn't available
        // (e.g. free Personal Team without the CloudKit entitlement).
        let cloudConfig = ModelConfiguration(cloudKitDatabase: .automatic)
        let localConfig = ModelConfiguration()
        do {
            container = try ModelContainer(for: schema, configurations: cloudConfig)
        } catch {
            do {
                container = try ModelContainer(for: schema, configurations: localConfig)
            } catch {
                if let support = FileManager.default
                    .urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                    for name in ["default.store", "default.store-shm", "default.store-wal"] {
                        try? FileManager.default.removeItem(at: support.appendingPathComponent(name))
                    }
                }
                container = try! ModelContainer(for: schema, configurations: localConfig)
            }
        }
        SampleData.seedIfNeeded(container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
