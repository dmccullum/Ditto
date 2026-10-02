import SwiftUI
import SwiftData
import AppIntents

@main
struct DittoiOSApp: App {
    /// One database shared with App Intents (Siri, Shortcuts, Spotlight).
    let container: ModelContainer = DittoStore.container
    @State private var settings = AppSettings()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Give the context its own undo manager. SwiftData then registers undo
        // operations and surfaces it to SwiftUI's environment, which enables the
        // system shake-to-undo and three-finger-swipe gestures on iOS.
        container.mainContext.undoManager = UndoManager()
        // Keep Spotlight and Siri's snippet vocabulary in sync with the library.
        Task { await Self.refreshSystemIndexes() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // Re-index on the way out so in-app edits reach Spotlight and Siri
            // without waiting for the next launch.
            if phase == .background {
                Task { await Self.refreshSystemIndexes() }
            }
        }
    }

    private static func refreshSystemIndexes() async {
        await DittoSpotlight.refresh()
        DittoShortcuts.updateAppShortcutParameters()
    }
}
