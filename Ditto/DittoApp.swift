//
//  DittoApp.swift
//  Ditto
//
//  Created by Daniel McCullum on 5/28/26.
//

import SwiftUI
import SwiftData
import AppKit
import AppIntents

/// Lets the app-level menu commands (⌘N etc.) ask the main window to act.
@Observable
final class AppCommands {
    var createSnippet = false
    var createCategory = false
    var exportLibrary = false
    var importLibrary = false
    var zoomIn = false
    var zoomOut = false
    var resetZoom = false
}

@main
struct DittoApp: App {
    /// One database, shared by every window/scene in the app — and with
    /// App Intents (Shortcuts, Spotlight). Built once in DittoStore.
    let container: ModelContainer = DittoStore.container
    @State private var commands = AppCommands()
    @State private var settings = AppSettings()

    init() {
        // Keep Spotlight and the Shortcuts snippet vocabulary in sync.
        Task {
            await DittoSpotlight.refresh()
            DittoShortcuts.updateAppShortcutParameters()
        }
    }

    var body: some Scene {
        // The full management window (sidebar + snippet cards). A single-instance
        // Window (not WindowGroup) so reopening it never spawns duplicates.
        Window("Ditto", id: "main") {
            ContentView()
                .environment(commands)
                .environment(settings)
                .onOpenURL { url in
                    SnippetURL.handle(url, context: container.mainContext,
                                      keepCategories: settings.linkCategoryBehavior == .keep)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .modelContainer(container)
        .commands {
            DittoCommands(commands: commands, settings: settings)
        }

        // The always-available menu bar dropdown for quick copying.
        MenuBarExtra("Ditto", systemImage: "doc.on.clipboard.fill") {
            MenuBarView()
                .modelContainer(container)
                .environment(settings)
        }
        .menuBarExtraStyle(.window)

        // Preferences (⌘,).
        Settings {
            SettingsView()
                .environment(settings)
        }

        // In-app user guide (Help → Ditto Help). A single-instance window.
        Window("Ditto Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)

        // Custom About window (Ditto → About Ditto).
        Window("About Ditto", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}

/// App menu commands. Lives in its own type so it can use `openWindow`, which
/// lets us reopen the main window even after it's been closed.
struct DittoCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var commands: AppCommands
    @Bindable var settings: AppSettings

    var body: some Commands {
        // Replace the default "New Window" (⌘N) with our own create actions.
        // These also reopen the window first, so they work even if it's closed.
        CommandGroup(replacing: .newItem) {
            Button("New Snippet") {
                showMainWindow()
                commands.createSnippet = true
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Category") {
                showMainWindow()
                commands.createCategory = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        // Export / Import under the File menu.
        CommandGroup(after: .newItem) {
            Divider()
            Button("Export Library…") { commands.exportLibrary = true }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Import Library…") { commands.importLibrary = true }
        }

        // Card size + grouping controls, added to the system View menu (rather
        // than a second "View" menu).
        CommandGroup(after: .sidebar) {
            Button("Default Size") { commands.resetZoom = true }
            Button("Zoom In") { commands.zoomIn = true }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { commands.zoomOut = true }
                .keyboardShortcut("-", modifiers: .command)
            Divider()
            Picker("Group By", selection: $settings.grouping) {
                ForEach(SnippetGrouping.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.inline)
            Divider()
        }

        // A reliable way back to the window after closing it.
        CommandGroup(after: .windowList) {
            Button("Ditto Window") { showMainWindow() }
                .keyboardShortcut("0", modifiers: .command)
        }

        // Replace the default Help item with our in-app guide.
        CommandGroup(replacing: .help) {
            Button("Ditto Help") {
                openWindow(id: "help")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("?", modifiers: .command)
        }

        // Replace the default About panel with our custom window.
        CommandGroup(replacing: .appInfo) {
            Button("About Ditto") {
                openWindow(id: "about")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
