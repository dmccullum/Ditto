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
import DMKit

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

/// What the Snippet menu acts on: the grid's selection, published by the
/// main window while it's focused and no sheet or dialog is up.
struct SnippetActions {
    var count: Int
    var allPinned: Bool
    /// The http(s) link a single selected snippet holds.
    var link: URL?
    /// Quick search's field has focus, so ⌘⌫ belongs to it, not Delete.
    var isEditingText: Bool
    var copy: () -> Void
    var preview: () -> Void
    var edit: () -> Void
    var duplicate: () -> Void
    var togglePin: () -> Void
    var copyShareLink: () -> Void
    var delete: () -> Void
}

/// What the Category menu acts on: the category selected in the sidebar.
struct CategoryActions {
    var edit: () -> Void
    var duplicate: () -> Void
    var copyShareLink: () -> Void
    var export: () -> Void
    var delete: () -> Void
}

/// Edit → Find Snippets…: opens quick search, or focuses its field when
/// it's already open.
struct FindSnippetsAction {
    var perform: () -> Void
    func callAsFunction() { perform() }
}

extension FocusedValues {
    @Entry var libraryActions: LibraryActions?
    @Entry var zoomActions: ZoomActions?
    @Entry var snippetActions: SnippetActions?
    @Entry var categoryActions: CategoryActions?
    @Entry var findSnippets: FindSnippetsAction?
}

@main
struct DittoApp: App {
    /// One database, shared by every window/scene in the app — and with
    /// App Intents (Shortcuts, Spotlight). Built once in DittoStore.
    let container: ModelContainer = DittoStore.container
    @State private var commands = AppCommands()
    @State private var settings = AppSettings()
    @State private var helpNavigation = HelpNavigation()

    init() {
        // Keep Spotlight and the Shortcuts snippet vocabulary in sync with
        // the library, including in-app edits while Ditto stays open.
        SystemIndexSync.start()
    }

    var body: some Scene {
        // The full management window (sidebar + snippet cards). A single-instance
        // Window (not WindowGroup) so reopening it never spawns duplicates.
        Window("Ditto", id: "main") {
            ContentView()
                .environment(commands)
                .environment(settings)
        }
        .defaultSize(width: 960, height: 640)
        .modelContainer(container)
        .commands {
            DittoCommands(commands: commands, helpNavigation: helpNavigation, settings: settings)
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

        // App › About Ditto.
        AboutScene(links: AboutLinks(sourceCode: URL(string: "https://github.com/dmccullum/Ditto"))) {
            AboutSignature()
        }

        // In-app user guide (Help → Ditto Help). A single-instance window.
        Window("Ditto Help", id: "help") {
            HelpView()
                .environment(helpNavigation)
        }
        .windowResizability(.contentSize)
        .commandsRemoved()

    }
}

/// App menu commands. Lives in its own type so it can use `openWindow`, which
/// lets us reopen the main window even after it's been closed.
struct DittoCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.libraryActions) private var libraryActions
    @FocusedValue(\.zoomActions) private var zoomActions
    @FocusedValue(\.snippetActions) private var snippetActions
    @FocusedValue(\.categoryActions) private var categoryActions
    @FocusedValue(\.findSnippets) private var findSnippets
    var commands: AppCommands
    var helpNavigation: HelpNavigation
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

        // Quick search, under Edit after the system Find items.
        CommandGroup(after: .textEditing) {
            Button("Find Snippets…") { findSnippets?() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(findSnippets == nil)
        }

        // Card size + grouping controls, added to the system View menu (rather
        // than a second "View" menu).
        CommandGroup(after: .sidebar) {
            Button("Default Size") { zoomActions?.reset() }
                .keyboardShortcut("0", modifiers: .command)
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

        // The grid selection. Same commands as a card's context menu.
        CommandMenu("Snippet") {
            let count = snippetActions?.count ?? 0
            Button(count > 1 ? "Copy \(count) Snippets" : "Copy") { snippetActions?.copy() }
                .disabled(count == 0)
            Button("Preview") { snippetActions?.preview() }
                .keyboardShortcut("y", modifiers: .command)
                .disabled(count != 1)
            Button("Edit…") { snippetActions?.edit() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(count != 1)
            Button("Duplicate") { snippetActions?.duplicate() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(count != 1)
            Button(snippetActions?.allPinned == true ? "Unpin" : "Pin") { snippetActions?.togglePin() }
                .disabled(count == 0)
            Button("Copy Share Link") { snippetActions?.copyShareLink() }
                .disabled(count != 1)
            Button("Open Link") {
                if let link = snippetActions?.link { NSWorkspace.shared.open(link) }
            }
            .disabled(snippetActions?.link == nil)
            Divider()
            Button(count > 1 ? "Delete \(count) Snippets" : "Delete Snippet") { snippetActions?.delete() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(count == 0 || snippetActions?.isEditingText == true)
        }

        // The category selected in the sidebar. Same commands as its
        // context menu.
        CommandMenu("Category") {
            Group {
                Button("Edit Category…") { categoryActions?.edit() }
                Button("Duplicate") { categoryActions?.duplicate() }
                Button("Copy Share Link") { categoryActions?.copyShareLink() }
                Button("Export Category…") { categoryActions?.export() }
                Divider()
                Button("Delete Category…") { categoryActions?.delete() }
            }
            .disabled(categoryActions == nil)
        }

        // The family Help menu, in FamilyHelpCommands' order.
        // TODO(DMKit): FamilyHelpCommands only takes a URL for “<App> Help”, and
        // Ditto's guide is an in-app window. Switch to it once `help` accepts a
        // Target (.action) as Keyboard Shortcuts does.
        CommandGroup(replacing: .help) {
            Button("Ditto Help") { showHelp() }
                .keyboardShortcut("?", modifiers: .command)
            Divider()
            Button("Keyboard Shortcuts") { showHelp(at: .shortcuts) }
            Button("Report an Issue…") {
                NSWorkspace.shared.open(URL(string: "https://github.com/dmccullum/Ditto/issues/new")!)
            }
        }

    }

    private func showHelp(at section: HelpNavigation.Section? = nil) {
        helpNavigation.pendingSection = section
        openWindow(id: "help")
        NSApp.activate()
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }
}
