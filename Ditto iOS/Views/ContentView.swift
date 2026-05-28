import SwiftUI
import SwiftData

enum SidebarSelection: Hashable {
    case all, pinned
    case category(Category)
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query(sort: \Snippet.sortIndex) private var allSnippets: [Snippet]

    @State private var selection: SidebarSelection? = .all
    @State private var searchText = ""
    @State private var isCreatingSnippet = false
    @State private var isCreatingCategory = false
    @State private var editingCategory: Category?

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
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isCreatingSnippet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
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
    }

    private var selectedCategory: Category? {
        if case .category(let cat) = selection { return cat }
        return nil
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
                Label("All Snippets", systemImage: "doc.on.doc")
                    .tag(SidebarSelection.all)
                if !pinnedSnippets.isEmpty {
                    Label("Pinned", systemImage: "pin.fill")
                        .tag(SidebarSelection.pinned)
                }
            }

            Section("Categories") {
                ForEach(categories) { category in
                    Label(category.name, systemImage: category.symbolName)
                        .foregroundStyle(SnippetColor.color(for: category.colorName))
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
                }
            }
        }
        .navigationTitle("Ditto")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isCreatingCategory = true } label: {
                    Image(systemName: "folder.badge.plus")
                }
            }
        }
    }
}
