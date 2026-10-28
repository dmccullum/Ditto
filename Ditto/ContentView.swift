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
import DMKit

/// What's selected in the sidebar.
enum SidebarSelection: Hashable {
    case all
    case frequent
    case category(Category)
}

/// A pending Save dialog: the JSON to write and the suggested file name.
struct PendingExport {
    let document: DittoDocument
    let filename: String
}

/// An error worth stopping for, shown as an alert.
struct AlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    // The snippets in the current drag (the whole selection when a selected
    // card is dragged), read from the drag session.
    @State private var draggedSnippetIDs: [PersistentIdentifier] = []

    // A local copy of the displayed snippets that we reorder live during a drag,
    // committing to the database only on drop. Keeping reordering out of the
    // database mid-drag prevents the grid from re-sorting under the cursor.
    @State private var displayOrder: [Snippet] = []

    // Which sidebar row is currently a drag-over target (for highlighting).
    @State private var dropTargetCategoryID: PersistentIdentifier?
    @State private var allRowIsDropTarget = false

    // Finder-style selection in the card grid. A plain click only copies,
    // but marks where ⇧-click and the arrow keys start from; ⌘-click,
    // ⇧-click, arrows, and ⌘A build a visible selection. The anchor is where
    // a ⇧-range starts; the cursor is where arrows move from.
    @State private var selectedSnippetIDs: Set<PersistentIdentifier> = []
    @State private var selectionAnchor: PersistentIdentifier?
    @State private var selectionCursor: PersistentIdentifier?
    @State private var scrollTarget: PersistentIdentifier?
    @State private var previewingSnippetID: PersistentIdentifier?
    @State private var flashingSnippetIDs: Set<PersistentIdentifier> = []
    @State private var gridSize: CGSize = .zero
    @FocusState private var gridIsFocused: Bool

    @State private var categoryPendingDeletion: Category?
    @State private var status: StatusMessage?
    @State private var pendingExport: PendingExport?
    @State private var isImporting = false
    @State private var alertMessage: AlertMessage?

    var body: some View {
        withCommands(windowContent)
    }

    private var windowContent: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            // Wide enough for quick search (520 pt) and the largest cards.
            detail
                .frame(minWidth: 540, minHeight: 360)
                .statusCapsule($status)
                .overlay(alignment: .top) {
                    if isQuickSearchPresented {
                        quickSearchPanel
                            .padding(.top, 28)
                            .transition(dropDownTransition)
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
            // ⌘= also zooms in: the menu's ⌘+ needs Shift on US layouts.
            Button("Zoom In") { sizeLevel = min(Self.maxSizeLevel, sizeLevel + 1) }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(sizeLevel >= Self.maxSizeLevel)
                .opacity(0)
                .accessibilityHidden(true)
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
        .fileExporter(
            isPresented: Binding(get: { pendingExport != nil },
                                 set: { if !$0 { pendingExport = nil } }),
            document: pendingExport?.document,
            contentType: .json,
            defaultFilename: pendingExport?.filename
        ) { result in
            if case .failure(let error) = result {
                showAlert("Couldn’t Save Export", message: error.localizedDescription)
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            importLibrary(result)
        }
        .alert(alertMessage?.title ?? "",
               isPresented: Binding(get: { alertMessage != nil },
                                    set: { if !$0 { alertMessage = nil } }),
               presenting: alertMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }

    /// The window's menu-command and event wiring, split from `body` to keep
    /// it type-checkable.
    private func withCommands(_ content: some View) -> some View {
        content
            .onOpenURL { url in
                openLink(url)
                NSApp.activate()
            }
            .onAppear { modelContext.undoManager = undoManager }
            .onChange(of: undoManager) { _, manager in modelContext.undoManager = manager }
            .onPasteCommand(of: [.plainText, .utf8PlainText]) { _ in
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
            .focusedSceneValue(\.libraryActions, LibraryActions(
                export: exportLibrary,
                import: { isImporting = true }
            ))
            .focusedSceneValue(\.snippetActions, isShowingModal ? nil : snippetActions)
            .focusedSceneValue(\.categoryActions, isShowingModal ? nil : categoryActions)
            .focusedSceneValue(\.findSnippets,
                               isShowingModal ? nil : FindSnippetsAction(perform: findSnippets))
            .focusedSceneValue(\.zoomActions, ZoomActions(
                canZoomIn: sizeLevel < Self.maxSizeLevel,
                canZoomOut: sizeLevel > Self.minSizeLevel,
                zoomIn: { sizeLevel = min(Self.maxSizeLevel, sizeLevel + 1) },
                zoomOut: { sizeLevel = max(Self.minSizeLevel, sizeLevel - 1) },
                reset: { sizeLevel = 2 }
            ))
            .onChange(of: draggedSnippetIDs) { old, new in
                // Snapshot the current order only when a drag begins. The rest of
                // the time the grid renders straight from the query, so ordinary
                // clicks don't pay for a mirror resync.
                if old.isEmpty && !new.isEmpty { displayOrder = filteredSnippets }
            }
            .onChange(of: quickSearchText) { _, _ in
                quickSearchSelection = quickSearchResults.first?.persistentModelID
            }
            .onChange(of: selection) { _, _ in clearSelection() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("All Snippets", systemImage: "tray.full.fill")
                    .badge(allSnippets.count)
                    .listRowBackground(dropHighlight(allRowIsDropTarget))
                    .tag(SidebarSelection.all)
                    .snippetDropTarget(isTargeted: $allRowIsDropTarget) { refile($0, to: nil) }

                Label {
                    Text("Frequent")
                } icon: {
                    Image(systemName: "flame.fill")
                        .symbolRenderingMode(.multicolor)
                }
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
                    Label("New Category", systemImage: "folder.badge.plus")
                }
                .help("New Category")
            }
        }
    }

    private func categoryRow(_ category: Category) -> some View {
        let accent = SnippetColor.color(for: category.colorName)
        let id = category.persistentModelID
        let isTarget = dropTargetCategoryID == id
        return Label {
            Text(category.name)
        } icon: {
            Image(systemName: category.symbolName)
                .foregroundStyle(accent)
        }
        .badge(category.snippets.count)
        .contentShape(Rectangle())
        .listRowBackground(dropHighlight(isTarget, tint: accent))
        .snippetDropTarget(isTargeted: Binding(
            get: { dropTargetCategoryID == id },
            set: { targeted in
                if targeted { dropTargetCategoryID = id }
                else if dropTargetCategoryID == id { dropTargetCategoryID = nil }
            }
        )) { refile($0, to: category) }
        .contextMenu {
            Button("Edit…") { editingCategory = category }
            Button("Duplicate") { duplicateCategory(category) }
            Divider()
            Button("Copy Share Link") { copyShareLink(for: category) }
            Button("Export…") { exportCategory(category) }
            Divider()
            Button("Delete…", role: .destructive) { categoryPendingDeletion = category }
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
        .onGeometryChange(for: CGSize.self) { $0.size } action: { gridSize = $0 }
        .dragContainer(for: DraggedSnippet.self, itemID: \.id) { ids in
            ids.compactMap { id in
                allSnippets.first { $0.persistentModelID == id }
                    .map { DraggedSnippet(id: id, content: $0.content) }
            }
        }
        .dragContainerSelection(Array(selectedSnippetIDs))
        .onDragSessionUpdated(trackDrag)
        .focusable()
        .focusEffectDisabled()
        .focused($gridIsFocused)
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
            moveSelection(press.key, extending: press.modifiers.contains(.shift))
            return .handled
        }
        .onKeyPress(.return) {
            guard !selectedSnippets.isEmpty else { return .ignored }
            copy(selectedSnippets)
            return .handled
        }
        .onKeyPress(.space) {
            guard let cursor = selectionCursor ?? selectedSnippets.first?.persistentModelID
            else { return .ignored }
            previewingSnippetID = previewingSnippetID == cursor ? nil : cursor
            return .handled
        }
        .onKeyPress(.escape) {
            guard !selectedSnippetIDs.isEmpty else { return .ignored }
            clearSelection()
            return .handled
        }
        .onDeleteCommand { delete(selectedSnippets) }
        .onCopyCommand {
            let snippets = selectedSnippets
            guard !snippets.isEmpty else { return [] }
            recordCopies(snippets)
            return [NSItemProvider(object: Clipboard.joined(snippets.map(\.content)) as NSString)]
        }
        .onCommand(#selector(NSResponder.selectAll(_:))) {
            let all = visibleSnippets
            selectedSnippetIDs = Set(all.map(\.persistentModelID))
            selectionAnchor = all.first?.persistentModelID
            selectionCursor = all.last?.persistentModelID
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
                        Label("Group By", systemImage: settings.grouping == .none
                              ? "rectangle.grid.1x2" : "rectangle.grid.1x2.fill")
                    }
                    .menuIndicator(.hidden)
                    .help("Group By")
                }

                Button { sizeLevel = max(Self.minSizeLevel, sizeLevel - 1) } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .disabled(sizeLevel <= Self.minSizeLevel)
                .help("Zoom Out")

                Button { sizeLevel = min(Self.maxSizeLevel, sizeLevel + 1) } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                .disabled(sizeLevel >= Self.maxSizeLevel)
                .help("Zoom In")

                Button { isCreatingSnippet = true } label: {
                    Label("New Snippet", systemImage: "plus")
                }
                .help("New Snippet")
            }

            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItem(placement: .primaryAction) {
                // A click toggles search; ⌘F (Edit → Find Snippets…) only
                // opens or refocuses it.
                Button {
                    if isQuickSearchPresented { dismissQuickSearch() }
                    else { beginQuickSearch() }
                } label: {
                    Label("Find Snippets", systemImage: "magnifyingglass")
                }
                .help("Find Snippets")
            }

        }
    }

    private var snippetGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: cardMinWidth), spacing: Self.gridSpacing)],
                    spacing: Self.gridSpacing
                ) {
                    if #available(macOS 27, *) {
                        ForEach(filteredSnippets) { snippet in
                            card(for: snippet)
                        }
                        .reorderable()
                    } else {
                        ForEach(gridSnippets) { snippet in
                            card(for: snippet)
                        }
                    }

                    // The add tile only appears in views you populate manually.
                    if isReorderable {
                        AddSnippetCard(sizeLevel: sizeLevel) { isCreatingSnippet = true }
                    }
                }
                .modifier(FlatReorderContainer(isEnabled: isReorderable) { sources, target in
                    moveSnippets(sources, before: target)
                })
                .padding(Self.gridPadding)
                .modifier(ClearsSelectionOnTap(minHeight: gridSize.height) {
                    clearSelection(); gridIsFocused = true
                })
            }
            .onChange(of: scrollTarget) { _, id in scroll(proxy, to: id) }
        }
    }

    private static let gridSpacing: CGFloat = 16
    private static let gridPadding: CGFloat = 20

    /// One card, wired to the grid's selection, copy, and reorder state.
    private func card(for snippet: Snippet) -> some View {
        let id = snippet.persistentModelID
        let targets = actionTargets(for: snippet)
        return SnippetCard(
            snippet: snippet,
            sizeLevel: sizeLevel,
            isSelected: selectedSnippetIDs.contains(id),
            isSelectionFocused: gridIsFocused,
            isFlashing: flashingSnippetIDs.contains(id),
            isShowingPreview: Binding(get: { previewingSnippetID == id },
                                      set: { previewingSnippetID = $0 ? id : nil }),
            isDragging: !draggedSnippetIDs.isEmpty,
            actionCount: targets.count,
            allTargetsPinned: targets.allSatisfy(\.isPinned),
            onClick: { click(snippet) },
            onCopy: { copy(actionTargets(for: snippet)) },
            onEdit: { editingSnippet = snippet },
            onDuplicate: { duplicate(snippet) },
            onCopyShareLink: { copyShareLink(for: snippet) },
            onTogglePin: { togglePin(actionTargets(for: snippet)) },
            onDelete: { delete(actionTargets(for: snippet)) },
            onReorder: { reorderSnippetsLocally(to: snippet) },
            onCommit: commitSnippetOrder
        )
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: PersistentIdentifier?) {
        guard let id else { return }
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
        scrollTarget = nil
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(snippetGroups) { group in
                        let collapsed = collapsedGroups.contains(group.id)
                        VStack(alignment: .leading, spacing: 12) {
                            groupHeader(group, collapsed: collapsed)
                            if !collapsed {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: cardMinWidth),
                                                       spacing: Self.gridSpacing)],
                                    spacing: Self.gridSpacing
                                ) {
                                    if #available(macOS 27, *) {
                                        ForEach(group.snippets) { snippet in
                                            card(for: snippet)
                                        }
                                        .reorderable(collectionID: group.id)
                                    } else {
                                        ForEach(group.snippets) { snippet in
                                            card(for: snippet)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .modifier(GroupedReorderContainer(isEnabled: isReorderable) { sources, target, group in
                    // Dropping into another category's section refiles there.
                    if settings.grouping == .category {
                        let category = categories.first { "cat:\($0.name)" == group }
                        if category != nil || group == "uncategorized" {
                            refile(sources, to: category)
                        }
                    }
                    moveSnippets(sources, before: target)
                })
                .padding(Self.gridPadding)
                .modifier(ClearsSelectionOnTap(minHeight: gridSize.height) {
                    clearSelection(); gridIsFocused = true
                })
            }
            .onChange(of: scrollTarget) { _, id in scroll(proxy, to: id) }
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
        case .category(let category):
            ContentUnavailableView {
                Label("No Snippets in “\(category.name)”", systemImage: category.symbolName)
            } description: {
                Text("Add a snippet here, or drag cards onto “\(category.name)” in the sidebar.")
            } actions: {
                Button("New Snippet", systemImage: "plus") { isCreatingSnippet = true }
                    .buttonStyle(.borderedProminent)
            }
        case .all:
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
        (draggedSnippetIDs.isEmpty || displayOrder.isEmpty) ? filteredSnippets : displayOrder
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
                Text("↑↓ Navigate")
                Text("↩ Copy")
                Text("⌘↩ Show in List")
                Spacer()
                Text("esc Close")
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
        .floatingGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func quickSearchRow(_ snippet: Snippet) -> some View {
        let selected = quickSearchSelection == snippet.persistentModelID
        let accent = snippet.tint

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
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        Task { quickSearchIsFocused = true }
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
        copy([snippet])
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

    /// Quick search slides down from the top, or just fades in with Reduce
    /// Motion.
    private var dropDownTransition: AnyTransition {
        DMMotion.transition(.move(edge: .top).combined(with: .opacity), reduceMotion: reduceMotion)
    }

    // MARK: - Menu commands

    /// A sheet, dialog, or file panel is up; the Snippet and Category menus
    /// and Find Snippets stay disabled until it's gone.
    private var isShowingModal: Bool {
        editingSnippet != nil || isCreatingSnippet || editingCategory != nil ||
        isCreatingCategory || pasteDraft != nil || categoryPendingDeletion != nil ||
        pendingExport != nil || isImporting || alertMessage != nil
    }

    private var snippetActions: SnippetActions {
        let targets = selectedSnippets
        let single = targets.count == 1 ? targets.first : nil
        return SnippetActions(
            count: targets.count,
            allPinned: !targets.isEmpty && targets.allSatisfy(\.isPinned),
            link: single?.urlValue,
            isEditingText: quickSearchIsFocused,
            copy: { copy(targets) },
            preview: {
                // Toggles, like Space and Quick Look's ⌘Y.
                guard let id = single?.persistentModelID else { return }
                if previewingSnippetID == id {
                    previewingSnippetID = nil
                } else {
                    scrollTarget = id
                    previewingSnippetID = id
                }
            },
            edit: { editingSnippet = single },
            duplicate: { if let single { duplicate(single) } },
            togglePin: { togglePin(targets) },
            copyShareLink: { if let single { copyShareLink(for: single) } },
            delete: { delete(targets) }
        )
    }

    private var categoryActions: CategoryActions? {
        guard let category = selectedCategory else { return nil }
        return CategoryActions(
            edit: { editingCategory = category },
            duplicate: { duplicateCategory(category) },
            copyShareLink: { copyShareLink(for: category) },
            export: { exportCategory(category) },
            delete: { categoryPendingDeletion = category }
        )
    }

    /// Edit → Find Snippets… (⌘F): opens quick search, or puts the cursor
    /// back in its field when it's already open.
    private func findSnippets() {
        if isQuickSearchPresented {
            quickSearchIsFocused = true
        } else {
            beginQuickSearch()
        }
    }

    // MARK: - Selection

    /// The grid as laid out on screen: rows of cards, section by section, so
    /// ↑/↓ land on the card visually above or below.
    private var gridRows: [[Snippet]] {
        let available = gridSize.width - Self.gridPadding * 2
        let columns = max(1, Int((available + Self.gridSpacing) / (cardMinWidth + Self.gridSpacing)))
        let sections = isGrouped
            ? snippetGroups.filter { !collapsedGroups.contains($0.id) }.map(\.snippets)
            : [gridSnippets]
        return sections.flatMap { items in
            stride(from: 0, to: items.count, by: columns).map {
                Array(items[$0..<min($0 + columns, items.count)])
            }
        }
    }

    /// Every card currently on screen, in reading order.
    private var visibleSnippets: [Snippet] { gridRows.flatMap { $0 } }

    private var selectedSnippets: [Snippet] {
        visibleSnippets.filter { selectedSnippetIDs.contains($0.persistentModelID) }
    }

    /// What a card's context menu acts on: the whole selection when the card
    /// is part of a multi-selection, otherwise just that card.
    private func actionTargets(for snippet: Snippet) -> [Snippet] {
        let id = snippet.persistentModelID
        guard selectedSnippetIDs.count > 1, selectedSnippetIDs.contains(id) else { return [snippet] }
        return selectedSnippets
    }

    private func click(_ snippet: Snippet) {
        let id = snippet.persistentModelID
        // The click's own flags, not the keyboard's state by the time the
        // button fires on mouse-up.
        let modifiers = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        gridIsFocused = true
        if modifiers.contains(.command) {
            if selectedSnippetIDs.remove(id) == nil { selectedSnippetIDs.insert(id) }
            selectionAnchor = id
            selectionCursor = id
        } else if modifiers.contains(.shift), let anchor = selectionAnchor {
            selectRange(from: anchor, to: id)
        } else {
            selectedSnippetIDs = []
            selectionAnchor = id
            selectionCursor = id
            copy([snippet])
        }
    }

    private func select(_ snippet: Snippet) {
        let id = snippet.persistentModelID
        selectedSnippetIDs = [id]
        selectionAnchor = id
        selectionCursor = id
    }

    private func selectRange(from anchor: PersistentIdentifier, to end: PersistentIdentifier) {
        let ids = visibleSnippets.map(\.persistentModelID)
        guard let a = ids.firstIndex(of: anchor), let b = ids.firstIndex(of: end) else { return }
        selectedSnippetIDs = Set(ids[min(a, b)...max(a, b)])
        selectionCursor = end
    }

    private func clearSelection() {
        selectedSnippetIDs = []
        selectionAnchor = nil
        selectionCursor = nil
    }

    private func moveSelection(_ key: KeyEquivalent, extending: Bool) {
        let rows = gridRows
        let all = rows.flatMap { $0 }
        guard let first = all.first else { return }
        guard let cursor = selectionCursor,
              let row = rows.firstIndex(where: { $0.contains { $0.persistentModelID == cursor } }),
              let column = rows[row].firstIndex(where: { $0.persistentModelID == cursor }),
              let index = all.firstIndex(where: { $0.persistentModelID == cursor })
        else {
            select(first)
            scrollTarget = first.persistentModelID
            return
        }

        let target: Snippet?
        switch key {
        case .leftArrow:  target = index > 0 ? all[index - 1] : nil
        case .rightArrow: target = index < all.count - 1 ? all[index + 1] : nil
        case .upArrow:    target = row > 0 ? rows[row - 1][min(column, rows[row - 1].count - 1)] : nil
        case .downArrow:
            target = row < rows.count - 1 ? rows[row + 1][min(column, rows[row + 1].count - 1)] : nil
        default:          target = nil
        }
        guard let target else { return }

        if extending {
            selectRange(from: selectionAnchor ?? cursor, to: target.persistentModelID)
        } else {
            select(target)
        }
        scrollTarget = target.persistentModelID
    }

    /// Copy one or more snippets, joined for pasting, and flash their cards.
    private func copy(_ snippets: [Snippet]) {
        guard !snippets.isEmpty else { return }
        Clipboard.copy(Clipboard.joined(snippets.map(\.content)))
        recordCopies(snippets)
    }

    private func recordCopies(_ snippets: [Snippet]) {
        // Usage telemetry shouldn't land on the undo stack.
        modelContext.withoutUndoRegistration {
            for snippet in snippets {
                snippet.copyCount += 1
                snippet.lastCopiedAt = .now
            }
            try? modelContext.save()
        }

        let ids = Set(snippets.map(\.persistentModelID))
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { flashingSnippetIDs.formUnion(ids) }
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(.easeOut(duration: 0.25)) { flashingSnippetIDs.subtract(ids) }
        }
    }

    private func togglePin(_ snippets: [Snippet]) {
        let pin = !snippets.allSatisfy(\.isPinned)
        for snippet in snippets { snippet.isPinned = pin }
        modelContext.undoManager?.setActionName(pin ? "Pin" : "Unpin")
        try? modelContext.save()
    }

    /// Delete as one undoable step, then select the next card, as Finder does.
    private func delete(_ snippets: [Snippet]) {
        guard !snippets.isEmpty else { return }
        let deleted = Set(snippets.map(\.persistentModelID))
        let all = visibleSnippets
        let lastIndex = all.lastIndex { deleted.contains($0.persistentModelID) } ?? 0
        let next = all[lastIndex...].first { !deleted.contains($0.persistentModelID) }
            ?? all[..<lastIndex].last { !deleted.contains($0.persistentModelID) }

        modelContext.deleteUndoably(snippets: snippets, actionName: snippets.count == 1
                                    ? "Delete Snippet" : "Delete \(snippets.count) Snippets")
        if let next { select(next) } else { clearSelection() }
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
            showAlert("Couldn’t Add from Link",
                      message: "Ditto can’t read this link. Check that it’s a complete ditto://add or ditto://import link.")
        } else if added == 0 {
            status = StatusMessage("Already in Your Library")
        } else {
            selection = .all
            status = StatusMessage(added == 1 ? "Added 1 Snippet" : "Added \(added) Snippets")
        }
    }

    private func deleteCategory(_ category: Category) {
        if selectedCategory?.persistentModelID == category.persistentModelID {
            selection = .all
        }
        modelContext.deleteUndoably(categories: [category], actionName: "Delete Category")
    }

    /// Duplicate a snippet into the slot right after it.
    private func duplicate(_ snippet: Snippet) {
        modelContext.insertUndoably(actionName: "Duplicate Snippet") {
            // Shift everything after the original down one slot so the copy's
            // position right after it is deterministic (no sortIndex ties).
            for other in allSnippets where other.sortIndex > snippet.sortIndex {
                other.sortIndex += 1
            }
            let copy = Snippet(
                title: snippet.title.isEmpty ? "" : snippet.title + " Copy",
                content: snippet.content,
                sortIndex: snippet.sortIndex + 1,
                isPinned: false,
                category: snippet.category
            )
            modelContext.insert(copy)
        }
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

    private func trackDrag(_ session: DragSession) {
        switch session.phase {
        case .initial, .active:
            if draggedSnippetIDs.isEmpty {
                draggedSnippetIDs = session.draggedItemIDs(for: PersistentIdentifier.self)
            }
        default:
            draggedSnippetIDs = []
        }
    }

    /// macOS 26 live reorder: moves the dragged cards, as a block, to the
    /// card under the pointer. Only the local copy changes, so the grid
    /// animates without the database re-sorting under the cursor.
    private func reorderSnippetsLocally(to target: Snippet) {
        let dragged = Set(draggedSnippetIDs)
        guard isReorderable, !dragged.contains(target.persistentModelID) else { return }
        var ordered = gridSnippets
        let moving = IndexSet(ordered.indices.filter { dragged.contains(ordered[$0].persistentModelID) })
        guard let from = moving.first,
              let to = ordered.firstIndex(where: { $0.persistentModelID == target.persistentModelID })
        else { return }

        // Moving toward a later position must insert *after* the target, hence
        // the +1; moving earlier inserts at the target. This makes dragging
        // down/right behave the same as up/left.
        ordered.move(fromOffsets: moving, toOffset: to > from ? to + 1 : to)

        withAnimation(.snappy(duration: 0.18)) {
            displayOrder = ordered
        }
    }

    /// macOS 26: on drop, persist the live order.
    private func commitSnippetOrder() {
        draggedSnippetIDs = []
        // A drop in a non-reorderable view (Frequently Used, Date Added
        // grouping) must not rewrite the manual order with that view's own.
        guard isReorderable, !displayOrder.isEmpty else { return }
        saveOrder(displayOrder)
    }

    /// macOS 27: a reorder container reported a move.
    private func moveSnippets(_ ids: [PersistentIdentifier], before target: PersistentIdentifier?) {
        var ordered = filteredSnippets
        let moving = ordered.filter { ids.contains($0.persistentModelID) }
        ordered.removeAll { ids.contains($0.persistentModelID) }
        let index = target.flatMap { id in ordered.firstIndex { $0.persistentModelID == id } }
            ?? ordered.endIndex
        ordered.insert(contentsOf: moving, at: index)
        withAnimation(.snappy(duration: 0.18)) { saveOrder(ordered) }
    }

    /// Write the shown order into `sortIndex`, keeping the slots of any
    /// snippets filtered out of the current view.
    private func saveOrder(_ shown: [Snippet]) {
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
        modelContext.undoManager?.setActionName("Reorder Snippets")
        try? modelContext.save()
    }

    /// Reorder categories via the sidebar List's native drag (preserves clicks).
    private func moveCategories(from source: IndexSet, to destination: Int) {
        var ordered = categories
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in ordered.enumerated() where category.sortIndex != index {
            category.sortIndex = index
        }
        modelContext.undoManager?.setActionName("Reorder Categories")
        try? modelContext.save()
    }

    /// Reassign dragged snippets' category (nil = uncategorized).
    private func refile(_ ids: [PersistentIdentifier], to category: Category?) {
        for snippet in allSnippets where ids.contains(snippet.persistentModelID) {
            snippet.category = category
        }
        modelContext.undoManager?.setActionName(
            "Move to \(category.map { "“\($0.name)”" } ?? "Uncategorized")")
        try? modelContext.save()
        draggedSnippetIDs = []
    }

    private func exportLibrary() {
        export(snippets: allSnippets, categories: categories,
               filename: "Ditto Library \(Date.now.formatted(.dateTime.year().month().day()))")
    }

    /// Export a single category (with its snippets) to a JSON file.
    private func exportCategory(_ category: Category) {
        export(snippets: category.snippets, categories: [category],
               filename: "Ditto - \(category.name)")
    }

    private func export(snippets: [Snippet], categories: [Category], filename: String) {
        do {
            let data = try exportDitto(snippets: snippets, categories: categories)
            pendingExport = PendingExport(document: DittoDocument(data: data), filename: filename)
        } catch {
            showAlert("Couldn’t Export", message: error.localizedDescription)
        }
    }

    private func showAlert(_ title: String, message: String) {
        alertMessage = AlertMessage(title: title, message: message)
    }

    /// Copy a self-contained `ditto://import` link for this category and its
    /// snippets to the clipboard — paste it anywhere (email, intranet) to share.
    private func copyShareLink(for category: Category) {
        guard let link = dittoImportLink(snippets: category.snippets, categories: [category]) else {
            showAlert("Couldn’t Create Share Link", message: "This category couldn’t be encoded.")
            return
        }
        Clipboard.copy(link.absoluteString)
    }

    /// Copy a self-contained ditto://import link for this snippet (and its
    /// category, so the recipient files it correctly) to the clipboard.
    private func copyShareLink(for snippet: Snippet) {
        let categories = snippet.category.map { [$0] } ?? []
        guard let link = dittoImportLink(snippets: [snippet], categories: categories) else {
            showAlert("Couldn’t Create Share Link", message: "This snippet couldn’t be encoded.")
            return
        }
        Clipboard.copy(link.absoluteString)
    }

    private func importLibrary(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            try modelContext.insertUndoably(actionName: "Import Library") {
                try importDitto(data: data, into: modelContext)
            }
        } catch {
            showAlert("Couldn’t Import Library", message: error.localizedDescription)
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
                      characters != " ",   // Space previews the selected card.
                      characters.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7f })
                else { return event }

                Task { self.onType(characters) }
                return nil
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        isolated deinit { uninstall() }
    }
}

/// Observes clicks throughout the window and dismisses quick search on any
/// click outside it in the content area. Clicks always reach the control
/// underneath; toolbar clicks leave search open, so the search button can
/// toggle it closed.
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
                guard let self, let view, let window = view.window, event.window === window,
                      window.contentLayoutRect.contains(event.locationInWindow) else { return event }
                let pointInPanel = view.convert(event.locationInWindow, from: nil)
                guard !view.bounds.contains(pointInPanel) else { return event }

                Task { self.onClickOutside() }
                return event
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        isolated deinit { uninstall() }
    }
}

/// Stretches the grid's content to fill the scroll view, so a click on the
/// empty space below the last card clears the selection too.
private struct ClearsSelectionOnTap: ViewModifier {
    let minHeight: CGFloat
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}

extension View {
    /// A sidebar row that takes cards dragged from the grid (but not text
    /// from other apps) and hands over their IDs from the drag session.
    func snippetDropTarget(isTargeted: Binding<Bool>,
                           perform: @escaping ([PersistentIdentifier]) -> Void) -> some View {
        self
            .dropDestination(for: String.self) { _, session in
                isTargeted.wrappedValue = false
                perform(session.localSession?.draggedItemIDs(for: PersistentIdentifier.self) ?? [])
            }
            .dropConfiguration { session in
                DropConfiguration(operation: session.localSession == nil ? .forbidden : .move)
            }
            .onDropSessionUpdated { session in
                switch session.phase {
                case .entering, .active: isTargeted.wrappedValue = session.localSession != nil
                default:                 isTargeted.wrappedValue = false
                }
            }
    }
}

/// macOS 27: the flat grid's reorder container. `target` is the card the
/// moved ones now sit before, or nil for the end.
private struct FlatReorderContainer: ViewModifier {
    let isEnabled: Bool
    let move: (_ sources: [PersistentIdentifier], _ target: PersistentIdentifier?) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 27, *) {
            content.reorderContainer(for: Snippet.self, isEnabled: isEnabled) { difference in
                move(difference.sources, difference.destination.position.target)
            }
        } else {
            content
        }
    }
}

/// macOS 27: the grouped grid's reorder container; each section is its own
/// collection, identified by its group ID.
private struct GroupedReorderContainer: ViewModifier {
    let isEnabled: Bool
    let move: (_ sources: [PersistentIdentifier], _ target: PersistentIdentifier?,
               _ group: String) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 27, *) {
            content.reorderContainer(for: Snippet.self, in: String.self,
                                     isEnabled: isEnabled) { difference in
                move(difference.sources, difference.destination.position.target,
                     difference.destination.collectionID)
            }
        } else {
            content
        }
    }
}

@available(macOS 27, *)
private extension ReorderDifference.Destination.Position {
    var target: ItemID? {
        switch self {
        case .before(let id): id
        case .end:            nil
        }
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
