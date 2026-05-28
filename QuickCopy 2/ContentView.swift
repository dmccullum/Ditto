//
//  ContentView.swift
//  QuickCopy 2
//
//  The main management window: a category sidebar on the left, a grid of
//  colorful snippet cards on the right.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// What's selected in the sidebar.
enum SidebarSelection: Hashable {
    case all
    case category(Category)
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCommands.self) private var appCommands
    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query(sort: \Snippet.sortIndex) private var allSnippets: [Snippet]

    @State private var selection: SidebarSelection = .all
    @State private var searchText = ""

    // Sheet state
    @State private var editingSnippet: Snippet?
    @State private var isCreatingSnippet = false
    @State private var editingCategory: Category?
    @State private var isCreatingCategory = false

    // The snippet currently being dragged, captured when the drag starts.
    @State private var draggedSnippet: Snippet?

    // A local copy of the displayed snippets that we reorder live during a drag,
    // committing to the database only on drop. Keeping reordering out of the
    // database mid-drag prevents the grid from re-sorting under the cursor.
    @State private var displayOrder: [Snippet] = []

    // Which sidebar row is currently a drag-over target (for highlighting).
    @State private var dropTargetCategoryID: PersistentIdentifier?
    @State private var allRowIsDropTarget = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .sheet(item: $editingSnippet) { SnippetEditor(snippet: $0) }
        .sheet(isPresented: $isCreatingSnippet) {
            SnippetEditor(snippet: nil, defaultCategory: selectedCategory)
        }
        .sheet(item: $editingCategory) { CategoryEditor(category: $0) }
        .sheet(isPresented: $isCreatingCategory) { CategoryEditor(category: nil) }
        .onChange(of: appCommands.createSnippet) { _, create in
            if create { isCreatingSnippet = true; appCommands.createSnippet = false }
        }
        .onChange(of: appCommands.createCategory) { _, create in
            if create { isCreatingCategory = true; appCommands.createCategory = false }
        }
        .onChange(of: draggedSnippet) { _, dragged in
            // Snapshot the current order only when a drag begins. The rest of
            // the time the grid renders straight from the query, so ordinary
            // clicks don't pay for a mirror resync.
            if dragged != nil { displayOrder = filteredSnippets }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Library") {
                HStack(spacing: 6) {
                    Image(systemName: "tray.full.fill")
                        .foregroundStyle(.tint)
                        .frame(width: 18)
                    Text("All Snippets")
                    Spacer()
                    Text("\(allSnippets.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.vertical, 2)
                .listRowBackground(dropHighlight(allRowIsDropTarget))
                .tag(SidebarSelection.all)
                .onDrop(
                    of: [.text],
                    delegate: UncategorizeDropDelegate(
                        draggedSnippet: $draggedSnippet,
                        highlighted: $allRowIsDropTarget,
                        onUncategorize: { move($0, to: nil) }
                    )
                )
            }

            Section("Categories") {
                ForEach(categories) { category in
                    categoryRow(category)
                        .tag(SidebarSelection.category(category))
                }
                .onMove(perform: moveCategories)
            }
        }
        .navigationTitle("QuickCopy")
        .frame(minWidth: 220)
        .safeAreaInset(edge: .bottom) {
            Button {
                isCreatingCategory = true
            } label: {
                Label("New Category", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }

    private func categoryRow(_ category: Category) -> some View {
        let accent = SnippetColor.color(for: category.colorName)
        let isTarget = dropTargetCategoryID == category.persistentModelID
        return HStack(spacing: 6) {
            Image(systemName: category.symbolName)
                .foregroundStyle(accent)
                .frame(width: 18)
            Text(category.name)
            Spacer()
            Text("\(category.snippets.count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .listRowBackground(dropHighlight(isTarget, tint: accent))
        .onDrop(
            of: [.text],
            delegate: CategoryDropDelegate(
                target: category,
                draggedSnippet: $draggedSnippet,
                highlightedCategoryID: $dropTargetCategoryID,
                onRefile: { move($0, to: category) }
            )
        )
        .contextMenu {
            Button("Edit…", systemImage: "pencil") { editingCategory = category }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                deleteCategory(category)
            }
        }
    }

    /// A rounded highlight shown behind a sidebar row while a snippet hovers over it.
    @ViewBuilder
    private func dropHighlight(_ active: Bool, tint: Color = .accentColor) -> some View {
        if active {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint.opacity(0.25))
        } else {
            Color.clear
        }
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            if filteredSnippets.isEmpty {
                emptyState
            } else {
                snippetGrid
            }
        }
        .navigationTitle(detailTitle)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search snippets")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreatingSnippet = true
                } label: {
                    Label("New Snippet", systemImage: "plus")
                }
            }
        }
    }

    private var snippetGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 16)],
                spacing: 16
            ) {
                ForEach(gridSnippets) { snippet in
                    SnippetCard(
                        snippet: snippet,
                        draggedSnippet: $draggedSnippet,
                        onEdit: { editingSnippet = snippet },
                        onReorder: { reorderSnippetLocally($0, target: $1) },
                        onCommit: commitSnippetOrder
                    )
                }
            }
            .padding(20)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Snippets Yet", systemImage: "sparkles")
        } description: {
            Text(searchText.isEmpty
                 ? "Add a snippet to start building your library."
                 : "No snippets match “\(searchText)”.")
        } actions: {
            if searchText.isEmpty {
                Button("New Snippet", systemImage: "plus") { isCreatingSnippet = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Derived data

    private var selectedCategory: Category? {
        if case let .category(category) = selection { return category }
        return nil
    }

    private var detailTitle: String {
        switch selection {
        case .all: return "All Snippets"
        case .category(let category): return category.name
        }
    }

    private var filteredSnippets: [Snippet] {
        var snippets = allSnippets

        if case let .category(category) = selection {
            snippets = snippets.filter { $0.category?.persistentModelID == category.persistentModelID }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            snippets = snippets.filter {
                $0.title.lowercased().contains(query) || $0.content.lowercased().contains(query)
            }
        }
        return snippets
    }

    /// What the grid renders: straight from the query normally, and from the
    /// local mirror only while a drag is in progress.
    private var gridSnippets: [Snippet] {
        (draggedSnippet == nil || displayOrder.isEmpty) ? filteredSnippets : displayOrder
    }

    // MARK: - Actions

    private func deleteCategory(_ category: Category) {
        if selectedCategory?.persistentModelID == category.persistentModelID {
            selection = .all
        }
        modelContext.delete(category)
        try? modelContext.save()
    }

    /// Live reorder during a drag — mutates only the local copy so the grid
    /// animates smoothly without the database re-sorting under the cursor.
    private func reorderSnippetLocally(_ dragged: Snippet, target: Snippet) {
        guard dragged.persistentModelID != target.persistentModelID else { return }
        var ordered = gridSnippets
        guard let from = ordered.firstIndex(where: { $0.persistentModelID == dragged.persistentModelID }),
              let to = ordered.firstIndex(where: { $0.persistentModelID == target.persistentModelID }) else { return }

        // Moving toward a later position must insert *after* the target, hence
        // the +1; moving earlier inserts at the target. This makes dragging
        // down/right behave the same as up/left.
        ordered.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)

        withAnimation(.snappy(duration: 0.18)) {
            displayOrder = ordered
        }
    }

    /// On drop, persist the local order into `sortIndex`, preserving the slots
    /// of any snippets filtered out of the current view.
    private func commitSnippetOrder() {
        let shown = displayOrder
        guard !shown.isEmpty else { return }
        let shownIDs = Set(shown.map(\.persistentModelID))
        var iterator = shown.makeIterator()

        var newGlobal: [Snippet] = []
        for snippet in allSnippets {
            if shownIDs.contains(snippet.persistentModelID) {
                if let next = iterator.next() { newGlobal.append(next) }
            } else {
                newGlobal.append(snippet)
            }
        }

        for (index, snippet) in newGlobal.enumerated() where snippet.sortIndex != index {
            snippet.sortIndex = index
        }
        draggedSnippet = nil
        try? modelContext.save()
    }

    /// Reorder categories via the sidebar List's native drag (preserves clicks).
    private func moveCategories(from source: IndexSet, to destination: Int) {
        var ordered = categories
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in ordered.enumerated() where category.sortIndex != index {
            category.sortIndex = index
        }
        try? modelContext.save()
    }

    /// Reassign a snippet's category (nil = uncategorized).
    private func move(_ snippet: Snippet, to category: Category?) {
        snippet.category = category
        try? modelContext.save()
    }
}

/// A category row accepts a dropped snippet to refile it into this category.
struct CategoryDropDelegate: DropDelegate {
    let target: Category
    @Binding var draggedSnippet: Snippet?
    @Binding var highlightedCategoryID: PersistentIdentifier?
    let onRefile: (Snippet) -> Void

    func validateDrop(info: DropInfo) -> Bool { draggedSnippet != nil }

    func dropEntered(info: DropInfo) {
        if draggedSnippet != nil {
            highlightedCategoryID = target.persistentModelID
        }
    }

    func dropExited(info: DropInfo) {
        if highlightedCategoryID == target.persistentModelID {
            highlightedCategoryID = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        if let snippet = draggedSnippet {
            onRefile(snippet)
        }
        draggedSnippet = nil
        highlightedCategoryID = nil
        return true
    }
}

/// The "All Snippets" row accepts a dropped snippet to clear its category.
struct UncategorizeDropDelegate: DropDelegate {
    @Binding var draggedSnippet: Snippet?
    @Binding var highlighted: Bool
    let onUncategorize: (Snippet) -> Void

    func validateDrop(info: DropInfo) -> Bool { draggedSnippet != nil }

    func dropEntered(info: DropInfo) {
        if draggedSnippet != nil { highlighted = true }
    }

    func dropExited(info: DropInfo) { highlighted = false }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        if let snippet = draggedSnippet { onUncategorize(snippet) }
        draggedSnippet = nil
        highlighted = false
        return true
    }
}

#Preview {
    ContentView()
        .environment(AppCommands())
        .modelContainer(for: [Snippet.self, Category.self], inMemory: true)
}
