//
//  QuickCopy_2App.swift
//  QuickCopy 2
//
//  Created by Daniel McCullum on 5/28/26.
//

import SwiftUI
import SwiftData

/// Lets the app-level menu commands (⌘N etc.) ask the main window to act.
@Observable
final class AppCommands {
    var createSnippet = false
    var createCategory = false
}

@main
struct QuickCopy_2App: App {
    /// One database, shared by every window/scene in the app. We build it once
    /// here and hand the same container to both the main window and the menu bar.
    let container: ModelContainer
    @State private var commands = AppCommands()

    init() {
        do {
            container = try ModelContainer(for: Snippet.self, Category.self)
        } catch {
            fatalError("Could not create the SwiftData container: \(error)")
        }
        // Seed example content on first launch.
        SampleData.seedIfNeeded(container.mainContext)
    }

    var body: some Scene {
        // The full management window (sidebar + snippet cards).
        WindowGroup(id: "main") {
            ContentView()
                .environment(commands)
        }
        .modelContainer(container)
        .commands {
            // Replace the default "New Window" (⌘N) with our own create actions.
            CommandGroup(replacing: .newItem) {
                Button("New Snippet") { commands.createSnippet = true }
                    .keyboardShortcut("n", modifiers: .command)
                Button("New Category") { commands.createCategory = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }

        // The always-available menu bar dropdown for quick copying.
        MenuBarExtra("QuickCopy", systemImage: "doc.on.clipboard.fill") {
            MenuBarView()
                .modelContainer(container)
        }
        .menuBarExtraStyle(.window)
    }
}
