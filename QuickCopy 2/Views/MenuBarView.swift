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
                ForEach(groupedSnippets, id: \.title) { group in
                    Text(group.title.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 2)

                    ForEach(group.snippets) { snippet in
                        MenuBarRow(
                            snippet: snippet,
                            justCopied: justCopiedID == snippet.persistentModelID,
                            action: { copy(snippet) }
                        )
                    }
                }
            }
            .padding(.bottom, 6)
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
                Label("Open QuickCopy", systemImage: "macwindow")
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quit QuickCopy")
        }
        .font(.callout)
        .padding(10)
    }

    // MARK: - Derived data

    private var filteredSnippets: [Snippet] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return allSnippets }
        return allSnippets.filter {
            $0.title.lowercased().contains(query) || $0.content.lowercased().contains(query)
        }
    }

    private struct Group {
        let title: String
        let snippets: [Snippet]
    }

    private var groupedSnippets: [Group] {
        var groups: [Group] = []
        for category in categories {
            let matches = filteredSnippets.filter {
                $0.category?.persistentModelID == category.persistentModelID
            }
            if !matches.isEmpty {
                groups.append(Group(title: category.name, snippets: matches))
            }
        }
        let uncategorized = filteredSnippets.filter { $0.category == nil }
        if !uncategorized.isEmpty {
            groups.append(Group(title: "Uncategorized", snippets: uncategorized))
        }
        return groups
    }

    // MARK: - Actions

    private func copy(_ snippet: Snippet) {
        Clipboard.copy(snippet.content)
        snippet.copyCount += 1
        snippet.lastCopiedAt = .now

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
