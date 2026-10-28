//
//  ContentView.swift
//  Ditto
//
//  The main management window: a category sidebar on the left, a grid of
//  colorful snippet cards on the right.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

/// What's selected in the sidebar.
enum SidebarSelection: Hashable {
    case all
    case frequent
    case category(Category)
}

/// A brief confirmation shown at the top of the window.
struct Banner: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let symbol: String
    let tint: Color
}

/// A pending "new snippet from pasted text" request.
struct PasteDraft: Identifiable {
    let id = UUID()
    let text: String
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Environment(AppCommands.self) private var appCommands
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Category.sortIndex) private var categories: [Category]
    @Query(sort: \Snippet.sortIndex) private var allSnippets: [Snippet]

    @State private var selection: SidebarSelection = .all
    @State private var isQuickSearchPresented = false
    @State private var quickSearchText = ""
    @State private var quickSearchSelection: PersistentIdentifier?
    @FocusState private var quickSearchIsFocused: Bool

    // Persisted card size: 0 = smallest … 4 = largest. The grid is adaptive,
    // so the number of columns follows the window width while cards stay near
    // the chosen size.
    @AppStorage("snippetSizeLevel") private var sizeLevel: Int = 2
    private static let minSizeLevel = 0
    private static let maxSizeLevel = 4

    /// Target minimum card width for each size level, fed to an adaptive grid.
    private var cardMinWidth: CGFloat {
        [150, 185, 225, 275, 330][min(max(sizeLevel, 0), 4)]
    }

    // In the All Snippets view, snippets can be grouped into collapsible
    // sections (by category or date added). The mode lives in AppSettings.
    @State private var collapsedGroups: Set<String> = []

    // Sheet / panel state
    @State private var editingSnippet: Snippet?
    @State private var isCreatingSnippet = false
    @State private var editingCategory: Category?
    @State private var isCreatingCategory = false
    @State private var pasteDraft: PasteDraft?

    // The snippet currently being dragged, captured when the drag starts.
    @State private var draggedSnippet: Snippet?

    // A local copy of the displayed snippets that we reorder live during a drag,
    // committing to the database only on drop. Keeping reordering out of the
    // database mid-drag prevents the grid from re-sorting under the cursor.
    @State private var displayOrder: [Snippet] = []

    // Which sidebar row is currently a drag-over target (for highlighting).
    @State private var dropTargetCategoryID: PersistentIdentifier?
    @State private var allRowIsDropTarget = false

    @State private var categoryPendingDeletion: Category?
    @State private var banner: Banner?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .overlay(alignment: .top) { bannerView }
                .overlay(alignment: .top) {
                    if isQuickSearchPresented {
                        quickSearchPanel
                            .padding(.top, 28)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
        }
        .background {
            TypeToSearchMonitor { characters in
                if isQuickSearchPresented {
                    quickSearchText.append(contentsOf: characters)
                    quickSearchIsFocused = true
                } else {
                    beginQuickSearch(with: characters)
                }
            }
        }
        .sheet(item: $editingSnippet) { SnippetEditor(snippet: $0) }
        .sheet(isPresented: $isCreatingSnippet) {
            SnippetEditor(snippet: nil, defaultCategory: selectedCategory)
        }
        .sheet(item: $editingCategory) { CategoryEditor(category: $0) }
        .sheet(isPresented: $isCreatingCategory) { CategoryEditor(category: nil) }
        .sheet(item: $pasteDraft) { draft in
            SnippetEditor(snippet: nil, defaultCategory: selectedCategory, defaultContent: draft.text)
        }
        .confirmDeletion(of: $categoryPendingDeletion, perform: deleteCategory)
        .onOpenURL { url in
            openLink(url)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onAppear { modelContext.undoManager = undoManager }
        .onChange(of: undoManager) { _, manager in modelContext.undoManager = manager }        .onPasteCommand(of: [.plainText, .utf8PlainText]) { _ in
            // Fires only when no text field consumes the paste, so normal
            // ⌘V in the search/editor fields still works.
            let text = NSPasteboard.general.string(forType: .string) ?? ""
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            pasteDraft = PasteDraft(text: text)
        }
        .onChange(of: appCommands.createSnippet, initial: true) { _, create in
            if create { isCreatingSnippet = true; appCommands.createSnippet = false }
        }
        .onChange(of: appCommands.createCategory, initial: true) { _, create in
            if create { isCreatingCategory = true; appCommands.createCategory = false }
        }
        .onChange(of: appCommands.exportLibrary) { _, export in
            if export {
                appCommands.exportLibrary = false
                DispatchQueue.main.async { runExport() }
            }
        }
        .onChange(of: appCommands.importLibrary) { _, imp in
            if imp { appCommands.importLibrary = false; DispatchQueue.main.async { runImport() } }
        }
        .onChange(of: appCommands.zoomIn) { _, v in
            if v { sizeLevel = min(Self.maxSizeLevel, sizeLevel + 1); appCommands.zoomIn = false }
        }
        .onChange(of: appCommands.zoomOut) { _, v in
            if v { sizeLevel = max(Self.minSizeLevel, sizeLevel - 1); appCommands.zoomOut = false }
        }
        .onChange(of: appCommands.resetZoom) { _, v in
            if v { sizeLevel = 2; appCommands.resetZoom = false }
        }
        .onChange(of: draggedSnippet) { _, dragged in
            // Snapshot the current order only when a drag begins. The rest of
            // the time the grid renders straight from the query, so ordinary
            // clicks don't pay for a mirror resync.
            if dragged != nil { displayOrder = filteredSnippets }
        }
        .onChange(of: quickSearchText) { _, _ in
            quickSearchSelection = quickSearchResults.first?.persistentModelID
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

                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 18)
                    Text("Frequent")
                    Spacer()
                }
                .padding(.vertical, 2)
                .tag(SidebarSelection.frequent)
            }

            Section("Categories") {
                ForEach(categories) { category in
                    categoryRow(category)
                        .tag(SidebarSelection.category(category))
                }
                .onMove(perform: moveCategories)
            }
        }
        .navigationTitle("Ditto")
        .frame(minWidth: 220)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    isCreatingCategory = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("New Category (⌘⇧N)")
            }
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
            Button("Duplicate", systemImage: "plus.square.on.square") { duplicateCategory(category) }
            Divider()
            Button("Copy Share Link", systemImage: "link") { copyShareLink(for: category) }
            Button("Export…", systemImage: "square.and.arrow.up") { exportCategory(category) }
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive) {
                categoryPendingDeletion = category
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
            } else if isGrouped {
                groupedSnippetView
            } else {
                snippetGrid
            }
        }
        .navigationTitle(detailTitle)
        .toolbar {
            // Native toolbar items: macOS auto-groups them into pills and fits
            // each button's highlight, matching system apps like Reminders.
            ToolbarItemGroup(placement: .primaryAction) {
                if isAllView {
                    Menu {
                        Picker("Group By", selection: groupingBinding) {
                            ForEach(SnippetGrouping.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Image(systemName: settings.grouping == .none
                              ? "rectangle.grid.1x2" : "rectangle.grid.1x2.fill")
                    }
                    .menuIndicator(.hidden)
                    .help("Group By")
                }

                Button { sizeLevel = max(Self.minSizeLevel, sizeLevel - 1) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .disabled(sizeLevel <= Self.minSizeLevel)
                .help("Zoom Out (⌘–)")

                Button { sizeLevel = min(Self.maxSizeLevel, sizeLevel + 1) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .disabled(sizeLevel >= Self.maxSizeLevel)
                .help("Zoom In (⌘+)")

                Button { isCreatingSnippet = true } label: {
                    Image(systemName: "plus")
                }
                .help("New Snippet (⌘N)")
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItem(placement: .primaryAction) {
                Button {
                    if isQuickSearchPresented { dismissQuickSearch() }
                    else { beginQuickSearch() }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)
                .help("Quick Search (⌘F)")
            }

        }
    }

    private var snippetGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: cardMinWidth), spacing: 16)],
                spacing: 16
            ) {
                ForEach(gridSnippets) { snippet in
                    SnippetCard(
                        snippet: snippet,
                        sizeLevel: sizeLevel,
                        draggedSnippet: $draggedSnippet,
                        onEdit: { editingSnippet = snippet },
                        onReorder: { reorderSnippetLocally($0, target: $1) },
                        onCommit: commitSnippetOrder
                    )
                }

                // The add tile only appears in views you populate manually.
                if isReorderable {
                    AddSnippetCard(sizeLevel: sizeLevel) { isCreatingSnippet = true }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Grouped view

    /// One collapsible section's worth of snippets in the grouped layout.
    private struct SnippetGroup: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let accent: Color
        let snippets: [Snippet]
    }

    private var snippetGroups: [SnippetGroup] {
        switch settings.grouping {
        case .category:  return categoryGroups
        case .dateAdded: return dateGroups
        case .none:      return []
        }
    }

    /// Group by category, in sidebar order, with uncategorized snippets last.
    /// Built from `gridSnippets` (not the raw query) so that mid-drag the
    /// sections track the live order and moves animate, same as the flat grid.
    private var categoryGroups: [SnippetGroup] {
        let snippets = gridSnippets
        var groups: [SnippetGroup] = []
        for category in categories {
            let items = snippets.filter {
                $0.category?.persistentModelID == category.persistentModelID
            }
            guard !items.isEmpty else { continue }
            groups.append(SnippetGroup(id: "cat:\(category.name)", title: category.name,
                                       symbol: category.symbolName,
                                       accent: SnippetColor.color(for: category.colorName),
                                       snippets: items))
        }
        let uncategorized = snippets.filter { $0.category == nil }
        if !uncategorized.isEmpty {
            groups.append(SnippetGroup(id: "uncategorized", title: "Uncategorized",
                                       symbol: "tray", accent: .secondary,
                                       snippets: uncategorized))
        }
        return groups
    }

    /// Group by date added, Finder-Recents style: Today, Yesterday, Previous 7
    /// Days, Previous 30 Days, then by month for the current year, then by year.
    private var dateGroups: [SnippetGroup] {
        let cal = Calendar.current
        let now = Date.now
        let startOfToday = cal.startOfDay(for: now)
        let startOfYesterday = cal.date(byAdding: .day, value: -1, to: startOfToday)!
        let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: startOfToday)!
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: startOfToday)!
        let startOfYear = cal.dateInterval(of: .year, for: now)?.start ?? startOfToday

        // Each bucket: a sort key (newest first) plus a stable id/title.
        func bucket(for date: Date) -> (sort: Date, id: String, title: String) {
            if date >= startOfToday      { return (startOfToday, "today", "Today") }
            if date >= startOfYesterday  { return (startOfYesterday, "yesterday", "Yesterday") }
            if date >= sevenDaysAgo      { return (sevenDaysAgo, "7d", "Previous 7 Days") }
            if date >= thirtyDaysAgo     { return (thirtyDaysAgo, "30d", "Previous 30 Days") }
            if date >= startOfYear {
                let comps = cal.dateComponents([.year, .month], from: date)
                let monthStart = cal.date(from: comps) ?? date
                return (monthStart, "m\(comps.year!)-\(comps.month!)",
                        monthStart.formatted(.dateTime.month(.wide)))
            }
            let year = cal.component(.year, from: date)
            let yearStart = cal.date(from: DateComponents(year: year)) ?? date
            return (yearStart, "y\(year)", "\(year)")
        }

        // Partition snippets into buckets, remembering each bucket's sort key.
        var byID: [String: (sort: Date, title: String, items: [Snippet])] = [:]
        for snippet in filteredSnippets {
            let b = bucket(for: snippet.createdAt)
            byID[b.id, default: (b.sort, b.title, [])].items.append(snippet)
        }

        return byID
            .sorted { $0.value.sort > $1.value.sort }
            .map { id, value in
                SnippetGroup(id: id, title: value.title, symbol: "calendar",
                             accent: .secondary,
                             snippets: value.items.sorted { $0.createdAt > $1.createdAt })
            }
    }

    private var groupedSnippetView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(snippetGroups) { group in
                    let collapsed = collapsedGroups.contains(group.id)
                    VStack(alignment: .leading, spacing: 12) {
                        groupHeader(group, collapsed: collapsed)
                        if !collapsed {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: cardMinWidth), spacing: 16)],
                                spacing: 16
                            ) {
                                ForEach(group.snippets) { snippet in
                                    SnippetCard(
                                        snippet: snippet,
                                        sizeLevel: sizeLevel,
                                        draggedSnippet: $draggedSnippet,
                                        onEdit: { editingSnippet = snippet },
                                        onReorder: { reorderSnippetLocally($0, target: $1) },
                                        onCommit: commitSnippetOrder
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func groupHeader(_ group: SnippetGroup, collapsed: Bool) -> some View {
        let accent = group.accent
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if collapsed { collapsedGroups.remove(group.id) }
                else { collapsedGroups.insert(group.id) }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                Image(systemName: group.symbol)
                    .foregroundStyle(accent)
                Text(group.title)
                    .font(.headline)
                Text("\(group.snippets.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var emptyState: some View {
        switch selection {
        case .frequent:
            ContentUnavailableView("Nothing Frequent Yet", systemImage: "flame",
                description: Text("Snippets you copy often will show up here."))
        default:
            ContentUnavailableView {
                Label("No Snippets Yet", systemImage: "sparkles")
            } description: {
                Text("Add a snippet to start building your library.")
            } actions: {
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
        case .frequent: return "Frequently Used"
        case .category(let category): return category.name
        }
    }

    private var isAllView: Bool {
        if case .all = selection { return true }
        return false
    }

    /// Grouped layout applies only to the All Snippets view, when enabled.
    private var isGrouped: Bool { settings.grouping != .none && isAllView }

    private var groupingBinding: Binding<SnippetGrouping> {
        Binding(get: { settings.grouping }, set: { settings.grouping = $0 })
    }

    /// Reordering only makes sense in the manually-ordered views. Date Added
    /// grouping is excluded: there the order is intrinsic (matches iOS).
    private var isReorderable: Bool {
        if isGrouped && settings.grouping == .dateAdded { return false }
        switch selection {
        case .all, .category: return true
        case .frequent: return false
        }
    }

    private var filteredSnippets: [Snippet] {
        var snippets: [Snippet]

        switch selection {
        case .all:
            // Pinned items float to the top; within each group, preserve sortIndex order.
            snippets = allSnippets.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.sortIndex < $1.sortIndex
            }
        case .category(let category):
            snippets = allSnippets
                .filter { $0.category?.persistentModelID == category.persistentModelID }
                .sorted {
                    if $0.isPinned != $1.isPinned { return $0.isPinned }
                    return $0.sortIndex < $1.sortIndex
                }
        case .frequent:
            snippets = allSnippets
                .filter { $0.copyCount > 0 }
                .sorted { $0.copyCount > $1.copyCount }
        }

        return snippets
    }

    /// What the grid renders: straight from the query normally, and from the
    /// local mirror only while a drag is in progress.
    private var gridSnippets: [Snippet] {
        (draggedSnippet == nil || displayOrder.isEmpty) ? filteredSnippets : displayOrder
    }

    // MARK: - Quick search

    private var quickSearchResults: [Snippet] {
        SnippetSearch.results(for: quickSearchText, in: allSnippets)
    }

    private var selectedQuickSearchSnippet: Snippet? {
        guard let id = quickSearchSelection else { return quickSearchResults.first }
        return quickSearchResults.first { $0.persistentModelID == id }
    }

    private var quickSearchPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search every snippet", text: $quickSearchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($quickSearchIsFocused)
                    .onKeyPress(.upArrow) {
                        moveQuickSearchSelection(by: -1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        moveQuickSearchSelection(by: 1)
                        return .handled
                    }
                    .onKeyPress(.return) {
                        if NSEvent.modifierFlags.contains(.command) {
                            revealQuickSearchSelection()
                        } else {
                            copyQuickSearchSelection()
                        }
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        dismissQuickSearch()
                        return .handled
                    }
                if !quickSearchText.isEmpty {
                    Button {
                        quickSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)

            Divider()

            if quickSearchResults.isEmpty {
                ContentUnavailableView.search(text: quickSearchText)
                    .frame(height: 180)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(quickSearchResults) { snippet in
                                quickSearchRow(snippet)
                                    .id(snippet.persistentModelID)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: quickSearchSelection) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }

            Divider()
            HStack(spacing: 14) {
                Label("navigate", systemImage: "arrow.up.arrow.down")
                Label("copy", systemImage: "return")
                Text("⌘↩ show in list")
                Spacer()
                Text("Esc to close")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 520)
        .background {
            ClickOutsideSearchMonitor(onClickOutside: dismissQuickSearch)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6))
        }
        // A broad ambient shadow plus tighter casts in both directions keeps
        // the panel distinct even over Ditto's dark toolbar and card grid.
        .shadow(color: .black.opacity(0.24), radius: 64, y: 10)
        .shadow(color: .black.opacity(0.30), radius: 26, y: 2)
        .shadow(color: .black.opacity(0.22), radius: 18, y: -8)
    }

    private func quickSearchRow(_ snippet: Snippet) -> some View {
        let selected = quickSearchSelection == snippet.persistentModelID
        let accent = SnippetColor.color(for: snippet.category?.colorName ?? "blue")

        return Button {
            quickSearchSelection = snippet.persistentModelID
            copyQuickSearchSelection()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: snippet.category?.symbolName ?? "doc.text")
                    .foregroundStyle(accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snippet.displayTitle)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(snippet.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let category = snippet.category {
                    Text(category.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? accent.opacity(0.18) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { quickSearchSelection = snippet.persistentModelID }
        }
    }

    private func beginQuickSearch(with characters: String = "") {
        quickSearchText = characters
        isQuickSearchPresented = true
        quickSearchSelection = SnippetSearch.results(for: characters, in: allSnippets).first?.persistentModelID
        DispatchQueue.main.async { quickSearchIsFocused = true }
    }

    private func dismissQuickSearch() {
        withAnimation(.easeOut(duration: 0.12)) { isQuickSearchPresented = false }
        quickSearchText = ""
        quickSearchSelection = nil
    }

    private func moveQuickSearchSelection(by offset: Int) {
        let results = quickSearchResults
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.persistentModelID == quickSearchSelection } ?? 0
        let next = min(max(current + offset, 0), results.count - 1)
        quickSearchSelection = results[next].persistentModelID
    }

    private func copyQuickSearchSelection() {
        guard let snippet = selectedQuickSearchSnippet else { return }
        Clipboard.copy(snippet.content)

        let undo = modelContext.undoManager
        undo?.disableUndoRegistration()
        snippet.copyCount += 1
        snippet.lastCopiedAt = .now
        try? modelContext.save()
        undo?.enableUndoRegistration()

        dismissQuickSearch()
    }

    private func revealQuickSearchSelection() {
        guard let snippet = selectedQuickSearchSnippet else { return }
        if let category = snippet.category {
            selection = .category(category)
        } else {
            selection = .all
        }
        dismissQuickSearch()
    }

    @ViewBuilder
    private var bannerView: some View {
        if let banner {
            Label(banner.message, systemImage: banner.symbol)
                .font(.callout.weight(.semibold))
                .fontDesign(.rounded)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(banner.tint)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { withAnimation { self.banner = nil } }
                .task(id: banner.id) {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation(.smooth) { self.banner = nil }
                }
        }
    }

    private func show(_ message: String, symbol: String, tint: Color) {
        withAnimation(.bouncy) { banner = Banner(message: message, symbol: symbol, tint: tint) }
    }

    // MARK: - Actions

    /// Handle a ditto:// link, then say what it did — a link that silently
    /// changes your library is a link you don't trust twice.
    private func openLink(_ url: URL) {
        let before = (try? modelContext.fetchCount(FetchDescriptor<Snippet>())) ?? 0
        let handled = modelContext.insertUndoably(actionName: "Add from Link") {
            SnippetURL.handle(url, context: modelContext,
                              keepCategories: settings.linkCategoryBehavior == .keep)
        }
        let added = ((try? modelContext.fetchCount(FetchDescriptor<Snippet>())) ?? 0) - before
        if !handled {
            show("That link couldn't be read", symbol: "exclamationmark.triangle.fill", tint: .orange)
        } else if added == 0 {
            show("Already in your library", symbol: "checkmark.circle.fill", tint: .secondary)
        } else {
            selection = .all
            show(added == 1 ? "Added 1 snippet" : "Added \(added) snippets",
                 symbol: "checkmark.circle.fill", tint: .green)
        }
    }

    private func deleteCategory(_ category: Category) {
        if selectedCategory?.persistentModelID == category.persistentModelID {
            selection = .all
        }
        modelContext.deleteUndoably(categories: [category], actionName: "Delete Category")
    }

    /// Duplicate a category and its snippets, then open the editor so the new
    /// copy can be renamed right away.
    private func duplicateCategory(_ category: Category) {
        let nextCategoryIndex = (categories.map(\.sortIndex).max() ?? -1) + 1
        let copy = Category(name: "\(category.name) copy",
                            symbolName: category.symbolName,
                            colorName: category.colorName,
                            sortIndex: nextCategoryIndex)
        modelContext.insertUndoably(actionName: "Duplicate Category") {
            modelContext.insert(copy)

            var nextSnippetIndex = (allSnippets.map(\.sortIndex).max() ?? -1) + 1
            for snippet in category.snippets.sorted(by: { $0.sortIndex < $1.sortIndex }) {
                let snippetCopy = Snippet(title: snippet.title, content: snippet.content,
                                          sortIndex: nextSnippetIndex, isPinned: snippet.isPinned,
                                          category: copy)
                modelContext.insert(snippetCopy)
                nextSnippetIndex += 1
            }
        }
        editingCategory = copy
    }

    /// Live reorder during a drag — mutates only the local copy so the grid
    /// animates smoothly without the database re-sorting under the cursor.
    private func reorderSnippetLocally(_ dragged: Snippet, target: Snippet) {
        guard isReorderable, dragged.persistentModelID != target.persistentModelID else { return }
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
        draggedSnippet = nil
        // A drop in a non-reorderable view (Frequently Used, Date Added
        // grouping) must not rewrite the manual order with that view's own.
        guard isReorderable else { return }
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

    private func runExport() {
        let data: Data
        do {
            data = try exportDitto(snippets: allSnippets, categories: categories)
        } catch {
            showAlert("Export failed", message: error.localizedDescription)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Ditto Library \(Date.now.formatted(.dateTime.year().month().day()))"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            showAlert("Could not write file", message: error.localizedDescription)
        }
    }

    private func showAlert(_ title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    /// Copy a self-contained `ditto://import` link for this category and its
    /// snippets to the clipboard — paste it anywhere (email, intranet) to share.
    private func copyShareLink(for category: Category) {
        guard let link = dittoImportLink(snippets: category.snippets, categories: [category]) else {
            showAlert("Couldn't create link", message: "This category couldn't be encoded.")
            return
        }
        Clipboard.copy(link.absoluteString)
    }

    /// Export a single category (with its snippets) to a JSON file.
    private func exportCategory(_ category: Category) {
        let data: Data
        do {
            data = try exportDitto(snippets: category.snippets, categories: [category])
        } catch {
            showAlert("Export failed", message: error.localizedDescription)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Ditto - \(category.name)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            showAlert("Could not write file", message: error.localizedDescription)
        }
    }

    private func runImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            try modelContext.insertUndoably(actionName: "Import Library") {
                try importDitto(data: data, into: modelContext)
            }
        } catch {
            showAlert("Import failed", message: error.localizedDescription)
        }
    }
}

/// Watches for ordinary typing while the main window is active. Text controls
/// retain their normal behavior; this only starts search from otherwise
/// unhandled typing in the window.
private struct TypeToSearchMonitor: NSViewRepresentable {
    let onType: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onType: onType) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onType = onType
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var onType: (String) -> Void
        weak var view: NSView?
        private var monitor: Any?

        init(onType: @escaping (String) -> Void) {
            self.onType = onType
        }

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let view, event.window === view.window,
                      view.window?.attachedSheet == nil else { return event }

                // Never steal keystrokes from search, editors, or any other text field.
                if view.window?.firstResponder is NSTextView ||
                    view.window?.firstResponder is NSTextField {
                    return event
                }

                let disallowed: NSEvent.ModifierFlags = [.command, .control, .option, .function]
                guard event.modifierFlags.intersection(disallowed).isEmpty,
                      let characters = event.characters,
                      !characters.isEmpty,
                      characters.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7f })
                else { return event }

                DispatchQueue.main.async { self.onType(characters) }
                return nil
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { uninstall() }
    }
}

/// Observes clicks throughout the window, consuming the first outside click so
/// it dismisses quick search without activating the control underneath.
private struct ClickOutsideSearchMonitor: NSViewRepresentable {
    let onClickOutside: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onClickOutside: onClickOutside) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onClickOutside = onClickOutside
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var onClickOutside: () -> Void
        weak var view: NSView?
        private var monitor: Any?

        init(onClickOutside: @escaping () -> Void) {
            self.onClickOutside = onClickOutside
        }

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
                [weak self] event in
                guard let self, let view, event.window === view.window else { return event }
                let pointInPanel = view.convert(event.locationInWindow, from: nil)
                guard !view.bounds.contains(pointInPanel) else { return event }

                DispatchQueue.main.async { self.onClickOutside() }
                // Treat search like a modal layer: the first outside click
                // dismisses it without activating the control underneath.
                return nil
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { uninstall() }
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
            presenting: category.wrappedValue
        ) { target in
            Button(count == 0 ? "Delete Category"
                   : count == 1 ? "Delete Category and 1 Snippet"
                   : "Delete Category and \(count) Snippets",
                   role: .destructive) {
                perform(target)
            }
        } message: { _ in
            Text(count == 0 ? "You can undo this with ⌘Z."
                 : "Its snippets are deleted too. You can undo this with ⌘Z.")
        }
    }
}
