import SwiftUI
import SwiftData

@main
struct DittoiOSApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([Snippet.self, Category.self])
        do {
            let config = ModelConfiguration(cloudKitDatabase: .automatic)
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            if let support = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                for name in ["default.store", "default.store-shm", "default.store-wal"] {
                    try? FileManager.default.removeItem(at: support.appendingPathComponent(name))
                }
            }
            let config = ModelConfiguration(cloudKitDatabase: .automatic)
            container = try! ModelContainer(for: schema, configurations: config)
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
