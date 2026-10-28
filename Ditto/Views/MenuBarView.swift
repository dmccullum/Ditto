//
//  MenuBarView.swift
//  Ditto
//
//  The dropdown that appears from the menu bar icon. Search, then click a
//  snippet, or pick one with ↑/↓ and press Return, to copy it.
//

import SwiftUI
import SwiftData
import AppKit

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query(sort: \Snippet.sortIndex) private var allSnippets: [Snippet]

    @State private var searchText = ""
    @State private var justCopiedID: PersistentIdentifier?
    /// The row ↑/↓ and the pointer move, and Return copies.
    @State private var highlightedRowID: String?
    /// Measured height of the list's content. A menu bar window sizes itself
    /// to its content, and a bare ScrollView has no natural height, so without
    /// this the list collapses to nothing and the menu looks empty.
    @State private var listContentHeight: CGFloat = 0
    @FocusState private var searchFocused: Bool
    @State private var hostWindow: NSWindow?
    private let maxListHeight: CGFloat = 380

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isSearching ? searchRows.isEmpty : allSnippets.isEmpty {
                emptyState
            } else {
                snippetList
            }

            Divider()
            footer
        }
        .frame(width: 320)
        // The menu bar window is reused between openings, so onAppear alone
        // only fires once; refocus every time it becomes key.
        .background(HostWindowReader(window: $hostWindow))
        .onAppear { focusSearch() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard let window = note.object as? NSWindow, window === hostWindow else { return }
            focusSearch()
        }
        .onChange(of: searchText) { _, _ in
            // While searching, Return copies the top match straight away.
            highlightedRowID = isSearching ? visibleRows.first?.id : nil
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search snippets", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onKeyPress(.downArrow) {
                    moveHighlight(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveHighlight(by: -1)
                    return .handled
                }
                .onKeyPress(.return) {
                    guard let row = highlightedRow else { return .ignored }
                    copy(row.snippet)
                    return .handled
                }
                .onKeyPress(.escape) {
                    // Esc clears the search first; with nothing to clear it
                    // falls through to the panel's own Esc handling.
                    guard !searchText.isEmpty else { return .ignored }
                    searchText = ""
                    return .handled
                }
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
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if isSearching {
                        // Search results are one ranked list, best match first.
                        ForEach(searchRows) { row in rowView(row) }
                    } else {
                        ForEach(displayGroups, id: \.title) { group in
                            sectionHeader(group)
                            if isExpanded(group.title) {
                                ForEach(group.rows) { row in rowView(row) }
                            }
                        }
                    }
                }
                .padding(.top, isSearching ? 6 : 0)
                .padding(.bottom, 6)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    listContentHeight = height
                }
            }
            .frame(height: min(max(listContentHeight, 44), maxListHeight))
            .onChange(of: highlightedRowID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    private func rowView(_ row: Row) -> some View {
        MenuBarRow(
            snippet: row.snippet,
            isHighlighted: highlightedRowID == row.id,
            justCopied: justCopiedID == row.snippet.persistentModelID,
            action: { copy(row.snippet) },
            onHover: { hovering in
                if hovering {
                    highlightedRowID = row.id
                } else if highlightedRowID == row.id {
                    highlightedRowID = nil
                }
            }
        )
        .id(row.id)
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
            Text(isSearching ? "No matches" : "No snippets yet")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: "main")
                NSApp.activate()
            } label: {
                Label("Open Ditto", systemImage: "macwindow")
            }
            .buttonStyle(.plain)

            Spacer()

            Button("Settings…") {
                NSApp.activate()
                openSettings()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut(",", modifiers: .command)

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quit Ditto")
            .accessibilityLabel("Quit Ditto")
        }
        .font(.callout)
        .padding(10)
    }

    // MARK: - Derived data

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Ranked the same way as the main window's quick search.
    private var searchRows: [Row] {
        makeRows(SnippetSearch.results(for: searchText, in: allSnippets), section: "Results")
    }

    /// The rows on screen, in order: what ↑/↓ step through.
    private var visibleRows: [Row] {
        if isSearching { return searchRows }
        return displayGroups.filter { isExpanded($0.title) }.flatMap(\.rows)
    }

    private var highlightedRow: Row? {
        guard let highlightedRowID else { return nil }
        return visibleRows.first { $0.id == highlightedRowID }
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

    /// What the list shows when not searching: a "Frequently Used" shortcut
    /// on top, then the per-category groups.
    private var displayGroups: [Group] {
        guard !isSearching else { return [] }
        var groups: [Group] = []
        if !frequentSnippets.isEmpty {
            groups.append(Group(title: "Frequently Used",
                                rows: makeRows(frequentSnippets, section: "Frequently Used")))
        }
        groups.append(contentsOf: groupedSnippets)
        return groups
    }

    private var groupedSnippets: [Group] {
        var groups: [Group] = []
        for category in categories {
            let matches = allSnippets.filter {
                $0.category?.persistentModelID == category.persistentModelID
            }
            if !matches.isEmpty {
                groups.append(Group(title: category.name, rows: makeRows(matches, section: category.name)))
            }
        }
        let uncategorized = allSnippets.filter { $0.category == nil }
        if !uncategorized.isEmpty {
            groups.append(Group(title: "Uncategorized", rows: makeRows(uncategorized, section: "Uncategorized")))
        }
        return groups
    }

    // MARK: - Actions

    private func moveHighlight(by offset: Int) {
        let rows = visibleRows
        guard !rows.isEmpty else { return }
        guard let current = rows.firstIndex(where: { $0.id == highlightedRowID }) else {
            highlightedRowID = (offset > 0 ? rows.first : rows.last)?.id
            return
        }
        highlightedRowID = rows[min(max(current + offset, 0), rows.count - 1)].id
    }

    /// Put the cursor in search so typing starts filtering right away.
    private func focusSearch() {
        Task { searchFocused = true }
    }

    private func copy(_ snippet: Snippet) {
        Clipboard.copy(snippet.content)
        // Usage telemetry shouldn't land on the undo stack.
        modelContext.withoutUndoRegistration {
            snippet.copyCount += 1
            snippet.lastCopiedAt = .now
            try? modelContext.save()
        }

        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
            justCopiedID = snippet.persistentModelID
        }
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(.easeOut(duration: 0.25)) {
                if justCopiedID == snippet.persistentModelID { justCopiedID = nil }
            }
        }
    }
}

/// Reports the NSWindow hosting a view, so the menu can tell when its own
/// window becomes key.
private struct HostWindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        // AppKit attaches the view mid-update; report on the next turn.
        WindowReportingView { newWindow in Task { window = newWindow } }
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowReportingView: NSView {
        let onWindowChange: (NSWindow?) -> Void

        init(onWindowChange: @escaping (NSWindow?) -> Void) {
            self.onWindowChange = onWindowChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange(window)
        }
    }
}

/// A single tappable row in the menu bar dropdown.
private struct MenuBarRow: View {
    let snippet: Snippet
    let isHighlighted: Bool
    let justCopied: Bool
    let action: () -> Void
    let onHover: (Bool) -> Void

    private var accent: Color {
        snippet.tint
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
                    .opacity(justCopied || isHighlighted ? 1 : 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(accent.opacity(isHighlighted ? 0.14 : 0))
                    .padding(.horizontal, 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}
