import SwiftUI
import SwiftData

@main
struct DittoiOSApp: App {
    let container: ModelContainer
    @State private var settings = AppSettings()

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
                // Last resort: the local store can't be opened. Move it aside —
                // never delete — so the data stays recoverable, then start fresh.
                StoreRecovery.backupStore()
                container = try! ModelContainer(for: schema, configurations: localConfig)
            }
        }
        SampleData.seedIfNeeded(container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .onOpenURL { url in
                    SnippetURL.handle(url, context: container.mainContext,
                                      keepCategories: settings.linkCategoryBehavior == .keep)
                }
        }
        .modelContainer(container)
    }
}
