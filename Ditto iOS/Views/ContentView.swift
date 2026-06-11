import SwiftUI
import SwiftData

enum SidebarSelection: Hashable {
    case all, pinned
    case category(Category)
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query(sort: \Snippet.sortIndex) private var allSnippets: [Snippet]

    @State private var selection: SidebarSelection? = .all
    @State private var searchText = ""
    @State private var isCreatingSnippet = false
    @State private var isCreatingCategory = false
    @State private var editingCategory: Category?
    @State private var isShowingSettings = false
    @State private var editMode: EditMode = .inactive

    private var pinnedSnippets: [Snippet] {
        allSnippets.filter { $0.isPinned }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            SnippetListView(
                selection: selection ?? .all,
                searchText: searchText,
                allSnippets: allSnippets
            )
            .environment(\.editMode, $editMode)
            .searchable(text: $searchText)
            .navigationTitle(navigationTitle)
            .toolbar {
                if isAllView {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Picker("Group By", selection: groupingBinding) {
                                ForEach(SnippetGrouping.allCases) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                        } label: {
                            Image(systemName: settings.grouping == .none
                                  ? "line.3.horizontal.decrease.circle"
                                  : "line.3.horizontal.decrease.circle.fill")
                        }
                    }
                }
                // Reordering applies everywhere except Date Added grouping,
                // where the order is intrinsic.
                if canReorder {
                    ToolbarItem(placement: .primaryAction) {
                        Button(editMode.isEditing ? "Done" : "Edit") {
                            withAnimation {
                                editMode = editMode.isEditing ? .inactive : .active
                            }
                        }
                    }
                }
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button { isCreatingSnippet = true } label: {
                        Label("New Snippet", systemImage: "square.and.pencil")
                    }
                }
            }
            .onChange(of: selection) { _, _ in editMode = .inactive }
            .onChange(of: settings.grouping) { _, _ in editMode = .inactive }
        }
        .sheet(isPresented: $isCreatingSnippet) {
            SnippetEditorView(defaultCategory: selectedCategory)
        }
        .sheet(isPresented: $isCreatingCategory) {
            CategoryEditorView()
        }
        .sheet(item: $editingCategory) { category in
            CategoryEditorView(category: category)
        }
        .background(ShakeUndoBridge(undoManager: modelContext.undoManager))
    }

    private var selectedCategory: Category? {
        if case .category(let cat) = selection { return cat }
        return nil
    }

    private var isAllView: Bool {
        if case .all? = selection { return true }
        return false
    }

    /// Reordering is meaningful everywhere except Date Added grouping, where
    /// order follows the dates. (Category view and category grouping allow it.)
    private var canReorder: Bool {
        !(isAllView && settings.grouping == .dateAdded)
    }

    private var groupingBinding: Binding<SnippetGrouping> {
        Binding(get: { settings.grouping }, set: { settings.grouping = $0 })
    }

    /// Duplicate a category and its snippets, then open the editor to rename.
    private func duplicateCategory(_ category: Category) {
        let nextCategoryIndex = (categories.map(\.sortIndex).max() ?? -1) + 1
        let copy = Category(name: "\(category.name) copy",
                            symbolName: category.symbolName,
                            colorName: category.colorName,
                            sortIndex: nextCategoryIndex)
        modelContext.insert(copy)

        var nextSnippetIndex = (allSnippets.map(\.sortIndex).max() ?? -1) + 1
        let members = allSnippets
            .filter { $0.category?.persistentModelID == category.persistentModelID }
            .sorted { $0.sortIndex < $1.sortIndex }
        for snippet in members {
            let snippetCopy = Snippet(title: snippet.title, content: snippet.content,
                                      sortIndex: nextSnippetIndex, isPinned: snippet.isPinned,
                                      category: copy)
            modelContext.insert(snippetCopy)
            nextSnippetIndex += 1
        }

        try? modelContext.save()
        editingCategory = copy
    }

    private var navigationTitle: String {
        switch selection ?? .all {
        case .all:    return "All Snippets"
        case .pinned: return "Pinned"
        case .category(let cat): return cat.name
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                Label { Text("All Snippets") } icon: {
                    sidebarChip("doc.on.doc", .blue)
                }
                .tag(SidebarSelection.all)
                if !pinnedSnippets.isEmpty {
                    Label { Text("Pinned") } icon: {
                        sidebarChip("pin.fill", .orange)
                    }
                    .tag(SidebarSelection.pinned)
                }
            }

            Section("Categories") {
                ForEach(categories) { category in
                    Label { Text(category.name) } icon: {
                        sidebarChip(category.symbolName,
                                    SnippetColor.color(for: category.colorName))
                    }
                    .tag(SidebarSelection.category(category))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(category)
                            } label: { Label("Delete", systemImage: "trash") }
                            Button { editingCategory = category } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button { editingCategory = category } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button { duplicateCategory(category) } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            if let link = dittoImportLink(snippets: category.snippets, categories: [category]) {
                                ShareLink(item: link) {
                                    Label("Share Link", systemImage: "square.and.arrow.up")
                                }
                            }
                            Divider()
                            Button(role: .destructive) {
                                modelContext.delete(category)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .navigationTitle("Ditto")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { isShowingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { isCreatingCategory = true } label: {
                    Image(systemName: "folder.badge.plus")
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
    }

    /// A Settings-style colored icon chip for sidebar rows.
    private func sidebarChip(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color.gradient)
            )
    }
}
