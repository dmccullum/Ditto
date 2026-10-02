import SwiftUI
import SwiftData

enum SidebarSelection: Hashable {
    case all, pinned, frequent
    case category(Category)
}

/// A transient confirmation that floats over the library (e.g. after a link import).
struct Banner: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let symbol: String
    let tint: Color
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query(sort: \Snippet.sortIndex) private var allSnippets: [Snippet]

    @State private var selection: SidebarSelection = .all
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var isCreatingSnippet = false
    @State private var isCreatingCategory = false
    @State private var editingCategory: Category?
    @State private var deletingCategory: Category?
    @State private var isShowingSettings = false
    @State private var isManagingCategories = false
    @State private var banner: Banner?

    var body: some View {
        Group {
            if sizeClass == .compact {
                NavigationStack { compactLibrary }
            } else {
                NavigationSplitView {
                    sidebar
                } detail: {
                    library.navigationTitle(selectionTitle)
                }
            }
        }
        .overlay(alignment: .top) { bannerView }
        .sheet(isPresented: $isCreatingSnippet) {
            SnippetEditorView(defaultCategory: selectedCategory)
        }
        .sheet(isPresented: $isCreatingCategory) {
            CategoryEditorView()
        }
        .sheet(item: $editingCategory) { category in
            CategoryEditorView(category: category)
        }
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
        .sheet(isPresented: $isManagingCategories) {
            NavigationStack { ManageCategoriesView(isModal: true) }
        }
        .confirmDeletion(of: $deletingCategory) { category in
            deleteCategory(category)
        }
        .onChange(of: categories) { _, current in
            // If the selected category disappears (deleted here, by undo, or
            // by sync), fall back to All rather than pointing at a dead row.
            if case .category(let selected) = selection,
               !current.contains(where: { $0.persistentModelID == selected.persistentModelID }) {
                selection = .all
            }
        }
        .onOpenURL(perform: openLink)
        .background(ShakeUndoBridge(undoManager: modelContext.undoManager))
    }

    // MARK: - Library

    /// The snippet list plus everything that rides along with it in both layouts.
    private var library: some View {
        SnippetListView(
            selection: selection,
            searchText: searchText,
            allSnippets: allSnippets,
            onNewSnippet: { isCreatingSnippet = true }
        )
        .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search all snippets")
        .toolbar {
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button { isCreatingSnippet = true } label: {
                    Label("New Snippet", systemImage: "square.and.pencil")
                }
            }
        }
    }

    /// iPhone: one screen — a wordmark up top, the category chips pinned
    /// beneath it, and the snippets.
    private var compactLibrary: some View {
        library
            .navigationTitle("Ditto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .safeAreaBar(edge: .top) {
                // Search spans every snippet, so the filters step aside.
                if searchText.isEmpty && settings.categoryNavigation == .chips {
                    CategoryChipBar(
                        selection: $selection,
                        categories: categories,
                        allSnippets: allSnippets,
                        onNewCategory: { isCreatingCategory = true },
                        onEdit: { editingCategory = $0 },
                        onDuplicate: duplicateCategory,
                        onDelete: { deletingCategory = $0 },
                        onManage: { isManagingCategories = true }
                    )
                }
            }
            .overlay {
                // Floats over the cards, stacked on the New Snippet button.
                if !isSearchPresented && settings.categoryNavigation == .rail {
                    CategoryRail(selection: $selection, categories: categories,
                                 allSnippets: allSnippets, side: settings.railSide)
                        .transition(.opacity)
                }
            }
            .animation(.snappy, value: settings.categoryNavigation)
            .animation(.snappy, value: isSearchPresented)
            .animation(.snappy, value: settings.railSide)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { wordmark }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .primaryAction) { moreMenu }
            }
    }

    private var wordmark: some View {
        HStack(spacing: 8) {
            DittoGlyph()
                .foregroundStyle(LinearGradient(
                    colors: [Color(red: 0.00, green: 0.38, blue: 1.00),
                             Color(red: 0.29, green: 0.77, blue: 0.77)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 26, height: 26)
            Text("Ditto")
                .font(.system(.title2, design: .rounded, weight: .bold))
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var moreMenu: some View {
        Menu {
            if case .all = selection {
                Picker(selection: groupingBinding) {
                    ForEach(SnippetGrouping.allCases) { option in
                        Text(option.label).tag(option)
                    }
                } label: {
                    Label("Group By", systemImage: "rectangle.grid.1x2")
                }
                .pickerStyle(.menu)
            }
            Picker(selection: navigationBinding) {
                ForEach(CategoryNavigation.allCases) { option in
                    Label(option.label, systemImage: option.symbol).tag(option)
                }
            } label: {
                Label("Category Style", systemImage: settings.categoryNavigation.symbol)
            }
            .pickerStyle(.menu)
            if settings.categoryNavigation == .rail {
                Picker(selection: railSideBinding) {
                    ForEach(RailSide.allCases) { side in
                        Text(side.label).tag(side)
                    }
                } label: {
                    Label("Rail Side", systemImage: "hand.raised")
                }
                .pickerStyle(.menu)
            }
            Button { isCreatingCategory = true } label: {
                Label("New Category", systemImage: "folder.badge.plus")
            }
            Button { isManagingCategories = true } label: {
                Label("Manage Categories", systemImage: "list.bullet")
            }
            Divider()
            Button { isShowingSettings = true } label: {
                Label("Settings", systemImage: "gearshape")
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
    }

    // MARK: - iPad sidebar

    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding(get: { selection }, set: { if let value = $0 { selection = value } })
    }

    private var sidebar: some View {
        List(selection: sidebarSelection) {
            Section {
                sidebarRow("All Snippets", symbol: "tray.full.fill", tint: .blue,
                           count: allSnippets.count)
                    .tag(SidebarSelection.all)
                sidebarRow("Pinned", symbol: "pin.fill", tint: .orange,
                           count: allSnippets.filter(\.isPinned).count)
                    .tag(SidebarSelection.pinned)
                sidebarRow("Frequent", symbol: "flame.fill", tint: .red, count: nil)
                    .tag(SidebarSelection.frequent)
            }

            Section("Categories") {
                ForEach(categories) { category in
                    sidebarRow(category.name, symbol: category.symbolName,
                               tint: SnippetColor.color(for: category.colorName),
                               count: category.snippets.count)
                        .tag(SidebarSelection.category(category))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { deletingCategory = category } label: {
                                Label("Delete", systemImage: "trash")
                            }
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
                            Button(role: .destructive) { deletingCategory = category } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onMove(perform: moveCategories)
            }
        }
        .navigationTitle("Ditto")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { isShowingSettings = true } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { isCreatingCategory = true } label: {
                    Label("New Category", systemImage: "folder.badge.plus")
                }
            }
            if case .all = selection {
                ToolbarItem(placement: .secondaryAction) {
                    Picker("Group By", selection: groupingBinding) {
                        ForEach(SnippetGrouping.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                }
            }
        }
    }

    private func sidebarRow(_ title: String, symbol: String, tint: Color, count: Int?) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                if let count {
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } icon: {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.gradient))
        }
    }

    // MARK: - Banner

    @ViewBuilder
    private var bannerView: some View {
        if let banner {
            Label(banner.message, systemImage: banner.symbol)
                .font(.subheadline.weight(.semibold))
                .fontDesign(.rounded)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(banner.tint)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { withAnimation { self.banner = nil } }
                .task(id: banner.id) {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation(.smooth) { self.banner = nil }
                }
                .sensoryFeedback(banner.symbol.contains("exclamation") ? .error : .success,
                                 trigger: banner.id)
        }
    }

    private func show(_ message: String, symbol: String, tint: Color) {
        withAnimation(.bouncy) { banner = Banner(message: message, symbol: symbol, tint: tint) }
    }

    // MARK: - Derived

    private var selectedCategory: Category? {
        if case .category(let cat) = selection { return cat }
        return nil
    }

    private var selectionTitle: String {
        switch selection {
        case .all:      return "All Snippets"
        case .pinned:   return "Pinned"
        case .frequent: return "Frequent"
        case .category(let cat): return cat.name
        }
    }

    private var navigationBinding: Binding<CategoryNavigation> {
        Binding(get: { settings.categoryNavigation }, set: { settings.categoryNavigation = $0 })
    }

    private var railSideBinding: Binding<RailSide> {
        Binding(get: { settings.railSide }, set: { settings.railSide = $0 })
    }

    private var groupingBinding: Binding<SnippetGrouping> {
        Binding(get: { settings.grouping }, set: { settings.grouping = $0 })
    }

    // MARK: - Actions

    /// Handle a ditto:// link, then say what it did — a link that silently
    /// changes your library is a link you don't trust twice.
    private func openLink(_ url: URL) {
        let before = (try? modelContext.fetchCount(FetchDescriptor<Snippet>())) ?? 0
        let handled = SnippetURL.handle(url, context: modelContext,
                                        keepCategories: settings.linkCategoryBehavior == .keep)
        let added = ((try? modelContext.fetchCount(FetchDescriptor<Snippet>())) ?? 0) - before
        if !handled {
            show("That link couldn't be read", symbol: "exclamationmark.triangle.fill", tint: .orange)
        } else if added == 0 {
            show("Already in your library", symbol: "checkmark.circle.fill", tint: .secondary)
        } else {
            selection = .all
            searchText = ""
            show(added == 1 ? "Added 1 snippet" : "Added \(added) snippets",
                 symbol: "checkmark.circle.fill", tint: .green)
        }
    }

    private func deleteCategory(_ category: Category) {
        if selectedCategory?.persistentModelID == category.persistentModelID {
            selection = .all
        }
        modelContext.delete(category)
        try? modelContext.save()
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        var ordered = categories
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in ordered.enumerated() where category.sortIndex != index {
            category.sortIndex = index
        }
        try? modelContext.save()
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
        selection = .category(copy)
        editingCategory = copy
    }
}

/// How to undo on this device: iPhones shake, iPads swipe.
let undoHint = UIDevice.current.userInterfaceIdiom == .pad
    ? "Swipe left with three fingers to undo."
    : "Shake your iPhone to undo."

extension View {
    /// Deleting a category cascades to its snippets, so it always asks first
    /// and says exactly how much is about to go.
    func confirmDeletion(of category: Binding<Category?>,
                         perform: @escaping (Category) -> Void) -> some View {
        let count = category.wrappedValue?.snippets.count ?? 0
        return confirmationDialog(
            "Delete “\(category.wrappedValue?.name ?? "")”?",
            isPresented: Binding(get: { category.wrappedValue != nil },
                                 set: { if !$0 { category.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: category.wrappedValue
        ) { target in
            Button(count == 0 ? "Delete Category"
                   : count == 1 ? "Delete Category and 1 Snippet"
                   : "Delete Category and \(count) Snippets",
                   role: .destructive) {
                perform(target)
            }
        } message: { _ in
            Text(count == 0 ? undoHint : "Its snippets are deleted too. \(undoHint)")
        }
    }
}
