//
//  MenuBarView.swift
//  QuickCopy 2
//
//  The dropdown that appears from the menu bar icon. Search, then click any
//  snippet to copy it instantly. Built for speed.
//

import SwiftUI
import SwiftData
import AppKit

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query(sort: \Snippet.sortIndex) private var allSnippets: [Snippet]

    @State private var searchText = ""
    @State private var justCopiedID: PersistentIdentifier?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if filteredSnippets.isEmpty {
                emptyState
            } else {
                snippetList
            }

            Divider()
            footer
        }
        .frame(width: 320)
        .frame(maxHeight: 460)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search snippets", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
    }

    private var snippetList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(displayGroups, id: \.title) { group in
                    sectionHeader(group)
                    if isExpanded(group.title) {
                        ForEach(group.rows) { row in
                            MenuBarRow(
                                snippet: row.snippet,
                                justCopied: justCopiedID == row.snippet.persistentModelID,
                                action: { copy(row.snippet) }
                            )
                        }
                    }
                }
            }
            .padding(.bottom, 6)
        }
    }

    private func sectionHeader(_ group: Group) -> some View {
        Button {
            toggle(group.title)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(isExpanded(group.title) ? 90 : 0))
                Text(group.title.uppercased())
                    .font(.caption2.weight(.semibold))
                Spacer()
                Text("\(group.rows.count)")
                    .font(.caption2)
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func isExpanded(_ title: String) -> Bool {
        // Always expand while searching so matches aren't hidden.
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return !settings.collapsedSections.contains(title)
    }

    private func toggle(_ title: String) {
        withAnimation(.snappy(duration: 0.18)) {
            if settings.collapsedSections.contains(title) {
                settings.collapsedSections.remove(title)
            } else {
                settings.collapsedSections.insert(title)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No snippets yet" : "No matches")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open Ditto", systemImage: "macwindow")
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quit Ditto")
        }
        .font(.callout)
        .padding(10)
    }

    // MARK: - Derived data

    private var filteredSnippets: [Snippet] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allSnippets }
        return allSnippets.filter {
            $0.title.localizedStandardContains(query) || $0.content.localizedStandardContains(query)
        }
    }

    /// A row carries a section-unique id so the same snippet can appear in both
    /// "Frequently Used" and its category without SwiftUI identity collisions.
    private struct Row: Identifiable {
        let id: String
        let snippet: Snippet
    }

    private struct Group {
        let title: String
        let rows: [Row]
    }

    private func makeRows(_ snippets: [Snippet], section: String) -> [Row] {
        snippets.map { Row(id: "\(section)-\($0.persistentModelID.hashValue)", snippet: $0) }
    }

    /// Top snippets by copy count, for the quick-access section.
    private var frequentSnippets: [Snippet] {
        Array(
            allSnippets
                .filter { $0.copyCount > 0 }
                .sorted { $0.copyCount > $1.copyCount }
                .prefix(5)
        )
    }

    /// What the list shows: a "Frequently Used" shortcut on top (when not
    /// searching), then the per-category groups.
    private var displayGroups: [Group] {
        var groups: [Group] = []
        if searchText.isEmpty && !frequentSnippets.isEmpty {
            groups.append(Group(title: "Frequently Used",
                                rows: makeRows(frequentSnippets, section: "Frequently Used")))
        }
        groups.append(contentsOf: groupedSnippets)
        return groups
    }

    private var groupedSnippets: [Group] {
        var groups: [Group] = []
        for category in categories {
            let matches = filteredSnippets.filter {
                $0.category?.persistentModelID == category.persistentModelID
            }
            if !matches.isEmpty {
                groups.append(Group(title: category.name, rows: makeRows(matches, section: category.name)))
            }
        }
        let uncategorized = filteredSnippets.filter { $0.category == nil }
        if !uncategorized.isEmpty {
            groups.append(Group(title: "Uncategorized", rows: makeRows(uncategorized, section: "Uncategorized")))
        }
        return groups
    }

    // MARK: - Actions

    private func copy(_ snippet: Snippet) {
        Clipboard.copy(snippet.content)
        // Usage telemetry shouldn't land on the undo stack.
        let undo = modelContext.undoManager
        undo?.disableUndoRegistration()
        snippet.copyCount += 1
        snippet.lastCopiedAt = .now
        try? modelContext.save()
        undo?.enableUndoRegistration()

        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
            justCopiedID = snippet.persistentModelID
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeOut(duration: 0.25)) {
                if justCopiedID == snippet.persistentModelID { justCopiedID = nil }
            }
        }
    }
}

/// A single tappable row in the menu bar dropdown.
private struct MenuBarRow: View {
    let snippet: Snippet
    let justCopied: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var accent: Color {
        SnippetColor.color(for: snippet.category?.colorName ?? "blue")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: snippet.category?.symbolName ?? "doc.text")
                    .font(.callout)
                    .foregroundStyle(accent)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(snippet.displayTitle)
                        .lineLimit(1)
                    Text(snippet.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: justCopied ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(justCopied ? accent : .secondary)
                    .opacity(justCopied || isHovering ? 1 : 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(accent.opacity(isHovering ? 0.14 : 0))
                    .padding(.horizontal, 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
