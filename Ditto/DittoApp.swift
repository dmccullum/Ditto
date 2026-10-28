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
}

/// Export / Import, published by the main window while it's focused. The
/// File menu items are disabled when it's closed or another window is key.
struct LibraryActions {
    var export: () -> Void
    var `import`: () -> Void
}

/// Card size controls, published by the main window while it's focused.
struct ZoomActions {
    var canZoomIn: Bool
    var canZoomOut: Bool
    var zoomIn: () -> Void
    var zoomOut: () -> Void
    var reset: () -> Void
}

extension FocusedValues {
    @Entry var libraryActions: LibraryActions?
    @Entry var zoomActions: ZoomActions?
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
        Task { await Self.refreshSystemIndexes() }
        // Ditto tends to stay open for days, so also re-index whenever it
        // loses focus — in-app edits reach Spotlight and Shortcuts without
        // waiting for the next launch.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { await Self.refreshSystemIndexes() }
        }
    }

    private static func refreshSystemIndexes() async {
        guard !DittoStore.isDemo else { return }
        await DittoSpotlight.refresh()
        DittoShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        // The full management window (sidebar + snippet cards). A single-instance
        // Window (not WindowGroup) so reopening it never spawns duplicates.
        Window("Ditto", id: "main") {
            ContentView()
                .environment(commands)
                .environment(settings)
        }
        .modelContainer(container)
        .commands {
            DittoCommands(commands: commands, settings: settings)
        }

        // The always-available menu bar dropdown for quick copying.
        MenuBarExtra {
            MenuBarView()
                .modelContainer(container)
                .environment(settings)
        } label: {
            Image(nsImage: .dittoMenuBarGlyph)
                .accessibilityLabel("Ditto")
        }
        .menuBarExtraStyle(.window)

        // Preferences (⌘,).
        Settings {
            SettingsView()
                .environment(settings)
                .modelContainer(container)
        }

        // In-app user guide (Help → Ditto Help). A single-instance window.
        Window("Ditto Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)

    }
}

/// App menu commands. Lives in its own type so it can use `openWindow`, which
/// lets us reopen the main window even after it's been closed.
struct DittoCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.libraryActions) private var libraryActions
    @FocusedValue(\.zoomActions) private var zoomActions
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
            Button("Export Library…") { libraryActions?.export() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(libraryActions == nil)
            Button("Import Library…") { libraryActions?.import() }
                .disabled(libraryActions == nil)
        }

        // Card size + grouping controls, added to the system View menu (rather
        // than a second "View" menu).
        CommandGroup(after: .sidebar) {
            Button("Default Size") { zoomActions?.reset() }
                .disabled(zoomActions == nil)
            Button("Zoom In") { zoomActions?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(zoomActions?.canZoomIn != true)
            Button("Zoom Out") { zoomActions?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(zoomActions?.canZoomOut != true)
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
                NSApp.activate()
            }
            .keyboardShortcut("?", modifiers: .command)
        }

        // Replace the default About panel with our custom window.
        CommandGroup(replacing: .appInfo) {
            Button("About Ditto") {
                NSApp.activate()
                AboutWindowController.shared.show()
            }
        }
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }
}
