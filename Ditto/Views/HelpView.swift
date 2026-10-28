//
//  HelpView.swift
//  Ditto
//
//  The in-app user guide, opened from Help → Ditto Help.
//

import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                section("Snippets", icon: "doc.text.fill", tint: .blue) {
                    bullet("Click a snippet card to copy it to the clipboard.")
                    bullet("⌘-click adds or removes cards from the selection; ⇧-click selects a range. Neither copies.")
                    bullet("With several cards selected, ⌘C copies them all: one per line for links, hashtags, and other short lines, with a blank line between longer snippets.")
                    bullet("Press ⌘N or the + button to add a new snippet.")
                    bullet("Right-click a card for Copy, Edit, Duplicate, Pin, Copy Share Link, Open Link (for URLs), and Delete.")
                    bullet("Drag a card to reorder it, drop it on a category to refile it, or drag it into another app as plain text.")
                }

                section("Quick Search", icon: "magnifyingglass", tint: .indigo) {
                    bullet("Start typing anywhere in the Ditto window, or press ⌘F, to search every snippet across all categories.")
                    bullet("Use ↑ and ↓ to choose a result. Press Return to copy it, or ⌘Return to show its category in the main list.")
                    bullet("Title matches appear before matches found only in snippet contents.")
                }

                section("Categories", icon: "folder.fill", tint: .orange) {
                    bullet("Add a category with the folder+ button above the sidebar (⇧⌘N).")
                    bullet("Right-click a category to Edit, Duplicate, Copy Share Link, Export, or Delete it.")
                    bullet("Pick a color and icon for each category when you create or edit it.")
                }

                section("Menu Bar", icon: "menubar.arrow.up.rectangle", tint: .purple) {
                    bullet("Click the Ditto icon in the menu bar for instant search-and-copy from anywhere.")
                    bullet("Copy any text elsewhere, then paste into Ditto's window to start a new snippet from it.")
                }

                section("Size & Grouping", icon: "square.grid.2x2.fill", tint: .green) {
                    bullet("Zoom In / Out (⌘+ / ⌘–) changes card size; Default Size resets it. Find these in the View menu or the toolbar.")
                    bullet("The grid reflows columns to fit the window automatically.")
                    bullet("In All Snippets, use View → Group By to group cards by Category or Date Added. Sections are collapsible.")
                }

                section("Sharing & Importing", icon: "square.and.arrow.up.fill", tint: .teal) {
                    bullet("Copy Share Link (on a snippet or category) puts a ditto:// link on the clipboard. Anyone who opens it adds those snippets to their library.")
                    bullet("File → Export Library… saves everything as a JSON file; Import Library… brings it back.")
                    bullet("Re-opening a link or re-importing a file is safe — Ditto merges by name and skips duplicates.")
                    bullet("Settings → Shared Links controls whether imported links keep their category or arrive uncategorized.")
                }

                section("Links", icon: "link", tint: .indigo) {
                    bullet("ditto://add?content=…&title=…&category=… adds a single snippet.")
                    bullet("ditto://import?data=… adds a bundle of snippets and/or whole categories.")
                    bullet("Values must be URL-encoded. Unknown categories are created automatically.")
                }

                section("Keyboard Shortcuts", icon: "keyboard.fill", tint: .pink) {
                    shortcut("⌘N", "New snippet")
                    shortcut("⇧⌘N", "New category")
                    shortcut("⌘F", "Quick search")
                    shortcut("⌘↩", "Show search result in list")
                    shortcut("⌘+ / ⌘–", "Zoom in / out")
                    shortcut("⇧⌘E", "Export library")
                    shortcut("↑ ↓ ← →", "Move the card selection (⇧ extends it)")
                    shortcut("↩", "Copy the selected cards")
                    shortcut("Space", "Preview the selected card")
                    shortcut("⌘A", "Select all cards")
                    shortcut("⌫", "Delete the selected cards")
                    shortcut("⌘Z / ⇧⌘Z", "Undo / redo")
                    shortcut("⌘0", "Show the Ditto window")
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520, height: 620)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ditto Help")
                    .font(.largeTitle.bold())
                Text("Your snippets, a click away.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func section<Content: View>(_ title: String, icon: String, tint: Color,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.title3.bold())
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(.secondary)
                .padding(.top, 5)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shortcut(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .frame(width: 96, alignment: .leading)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    HelpView()
}
