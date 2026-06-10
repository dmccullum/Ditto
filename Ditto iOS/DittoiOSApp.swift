import SwiftUI
import SwiftData
import AppIntents

@main
struct DittoiOSApp: App {
    /// One database shared with App Intents (Siri, Shortcuts, Spotlight).
    let container: ModelContainer = DittoStore.container
    @State private var settings = AppSettings()

    init() {
        // Give the context its own undo manager. SwiftData then registers undo
        // operations and surfaces it to SwiftUI's environment, which enables the
        // system shake-to-undo and three-finger-swipe gestures on iOS.
        container.mainContext.undoManager = UndoManager()
        // Keep Spotlight and Siri's snippet vocabulary in sync with the library.
        Task {
            await DittoSpotlight.refresh()
            DittoShortcuts.updateAppShortcutParameters()
        }
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
