import SwiftUI
import SwiftData

struct SnippetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings

    let selection: SidebarSelection
    let searchText: String
    let allSnippets: [Snippet]
    var onNewSnippet: () -> Void = {}

    @State private var editingSnippet: Snippet?
    @State private var copiedSnippetID: PersistentIdentifier?
    @State private var collapsedGroups: Set<String> = []
    @State private var deletedTitle: String?
    @State private var deleteCount = 0

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filtered: [Snippet] {
        // Search looks through every snippet, whatever filter is showing, and
        // ranks title matches first — the same rules as the Mac's Quick Search.
        if isSearching {
            return SnippetSearch.results(for: searchText, in: allSnippets)
        }
        // Otherwise ordered purely by sortIndex (allSnippets is already
        // @Query-sorted that way). Pinning does NOT float items to the top —
        // it only adds a badge — so a pin never reorders the list. The Pinned
        // filter is how you gather pinned snippets together.
        switch selection {
        case .all:
            return allSnippets
        case .pinned:
            return allSnippets.filter { $0.isPinned }
        case .frequent:
            return allSnippets
                .filter { $0.copyCount > 0 }
                .sorted { $0.copyCount > $1.copyCount }
        case .category(let cat):
            return allSnippets.filter { $0.category?.persistentModelID == cat.persistentModelID }
        }
    }

    /// Drag-to-reorder only where the order on screen is the manual order.
    private var isReorderable: Bool {
        if isSearching { return false }
        if case .frequent = selection { return false }
        if isGrouped && settings.grouping == .dateAdded { return false }
        return true
    }

    private var showsCopyCounts: Bool {
        if case .frequent = selection, !isSearching { return true }
        return false
    }

    var body: some View {
        Group {
            if filtered.isEmpty {
                emptyState
            } else if isGrouped {
                groupedList
            } else {
                flatList
            }
        }
        .overlay(alignment: .bottom) { undoToast }
        .sheet(item: $editingSnippet) { SnippetEditorView(snippet: $0) }
        // The copy is the app's whole job; it should be felt, not just seen.
        .sensoryFeedback(.success, trigger: copiedSnippetID) { _, new in new != nil }
        .sensoryFeedback(.impact(weight: .medium), trigger: deleteCount)
    }

    // MARK: - Empty states

    @ViewBuilder
    private var emptyState: some View {
        if isSearching {
            ContentUnavailableView.search(text: searchText)
        } else {
            switch selection {
            case .pinned:
                ContentUnavailableView("Nothing Pinned", systemImage: "pin",
                    description: Text("Swipe right on a snippet to pin the ones you reach for most."))
            case .frequent:
                ContentUnavailableView("Nothing Frequent Yet", systemImage: "flame",
                    description: Text("Copy a few snippets and your regulars will show up here."))
            case .category(let category):
                ContentUnavailableView {
                    Label("No \(category.name) Yet", systemImage: category.symbolName)
                        .foregroundStyle(SnippetColor.color(for: category.colorName))
                } description: {
                    Text("Snippets you add here are one tap from your clipboard.")
                } actions: {
                    Button("New Snippet", action: onNewSnippet)
                        .buttonStyle(.borderedProminent)
                        .tint(SnippetColor.color(for: category.colorName))
                }
            case .all:
                ContentUnavailableView {
                    VStack(spacing: 16) {
                        DittoMarkTile(size: 72)
                        Text("Nothing to Ditto Yet")
                    }
                } description: {
                    Text("Save the things you type again and again — hashtags, links, replies — then tap to copy.")
                } actions: {
                    Button("New Snippet", action: onNewSnippet)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // MARK: - Lists

    private var flatList: some View {
        List {
            ForEach(filtered) { snippet in rowView(snippet) }
                .onMove(perform: isReorderable ? { moveSnippets(from: $0, to: $1) } : nil)
        }
        .listStyle(.plain)
        .animation(.snappy, value: filtered.map(\.persistentModelID))
    }

    private var groupedList: some View {
        List {
            ForEach(snippetGroups) { group in
                Section {
                    if !collapsedGroups.contains(group.id) {
                        ForEach(group.snippets) { snippet in rowView(snippet) }
                            .onMove(perform: isReorderable
                                    ? { source, dest in moveSnippets(in: group, from: source, to: dest) }
                                    : nil)
                    }
                } header: {
                    groupHeader(group)
                }
            }
        }
        // Plain, like the flat list: rows draw their own cards, so
        // inset-grouped margins would only make them narrower.
        .listStyle(.plain)
    }

    /// Reorder via long-press drag. Only the visible snippets trade places;
    /// everything filtered out keeps its slot, so reordering inside a
    /// category never scrambles the All Snippets order.
    private func moveSnippets(from source: IndexSet, to destination: Int) {
        var items = filtered
        items.move(fromOffsets: source, toOffset: destination)
        commitOrder(of: items)
    }

    /// Reorder within a single group, then commit the whole displayed order
    /// so the query order matches the screen immediately — no post-drag
    /// reshuffle.
    private func moveSnippets(in group: SnippetGroup, from source: IndexSet, to destination: Int) {
        var groupItems = group.snippets
        groupItems.move(fromOffsets: source, toOffset: destination)

        var fullOrder: [Snippet] = []
        for g in snippetGroups {
            fullOrder.append(contentsOf: g.id == group.id ? groupItems : g.snippets)
        }
        commitOrder(of: fullOrder)
    }

    private func commitOrder(of shown: [Snippet]) {
        let shownIDs = Set(shown.map(\.persistentModelID))
        var replacements = shown.makeIterator()
        var global: [Snippet] = []
        for snippet in allSnippets {
            if shownIDs.contains(snippet.persistentModelID) {
                if let next = replacements.next() { global.append(next) }
            } else {
                global.append(snippet)
            }
        }
        for (index, snippet) in global.enumerated() where snippet.sortIndex != index {
            snippet.sortIndex = index
        }
        try? modelContext.save()
    }

    // MARK: - Rows

    @ViewBuilder
    private func rowView(_ snippet: Snippet) -> some View {
        SnippetRow(snippet: snippet,
                   isCopied: copiedSnippetID == snippet.persistentModelID,
                   showsCopyCount: showsCopyCounts)
            // Rows draw their own accent-tinted cards (matching the Mac app),
            // so the List chrome — separators and row backgrounds — goes away.
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .contentShape(.rect(cornerRadius: 18))
            .onTapGesture { copy(snippet) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Copies to the clipboard")
            .accessibilityAction(named: "Edit") { editingSnippet = snippet }
            .swipeActions(edge: .leading) {
                Button { togglePin(snippet) } label: {
                    Label(snippet.isPinned ? "Unpin" : "Pin",
                          systemImage: snippet.isPinned ? "pin.slash.fill" : "pin.fill")
                }
                .tint(.orange)
            }
            // Delete + Edit on the trailing edge. Full swipe is off so the
            // gesture only reveals the buttons — delete takes a deliberate tap,
            // and the undo toast catches the rest.
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) { delete(snippet) } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button { editingSnippet = snippet } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.gray)
            }
            .contextMenu {
                Button { copy(snippet) } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button { editingSnippet = snippet } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button { duplicate(snippet) } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Button { togglePin(snippet) } label: {
                    Label(snippet.isPinned ? "Unpin" : "Pin",
                          systemImage: snippet.isPinned ? "pin.slash" : "pin")
                }
                if let url = snippet.urlValue {
                    Button { UIApplication.shared.open(url) } label: {
                        Label("Open Link", systemImage: "safari")
                    }
                }
                Section {
                    ShareLink(item: snippet.content) {
                        Label("Share Text", systemImage: "square.and.arrow.up")
                    }
                    if let link = shareLink(for: snippet) {
                        ShareLink(item: link) {
                            Label("Share as Ditto Link", systemImage: "link")
                        }
                    }
                }
                Divider()
                Button(role: .destructive) { delete(snippet) } label: {
                    Label("Delete", systemImage: "trash")
                }
            } preview: {
                SnippetPreview(snippet: snippet)
            }
    }

    private func groupHeader(_ group: SnippetGroup) -> some View {
        let collapsed = collapsedGroups.contains(group.id)
        return Button {
            withAnimation(.snappy) {
                if collapsed { collapsedGroups.remove(group.id) }
                else { collapsedGroups.insert(group.id) }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: group.symbol)
                    .foregroundStyle(group.tint)
                Text(group.title)
                    .font(.headline)
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)
                Text("\(group.snippets.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .accessibilityLabel("\(group.title), \(group.snippets.count) snippets")
        .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
    }

    // MARK: - Undo toast

    @ViewBuilder
    private var undoToast: some View {
        if let deletedTitle {
            HStack(spacing: 14) {
                Text("Deleted “\(deletedTitle)”")
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Button("Undo") {
                    modelContext.undoManager?.undo()
                    try? modelContext.save()
                    withAnimation(.snappy) { self.deletedTitle = nil }
                }
                .fontWeight(.semibold)
            }
            .font(.subheadline)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular.interactive(), in: .capsule)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: deleteCount) {
                try? await Task.sleep(for: .seconds(4))
                withAnimation(.smooth) { self.deletedTitle = nil }
            }
        }
    }

    // MARK: - Actions

    /// A self-contained ditto://import link for this snippet (and its category).
    private func shareLink(for snippet: Snippet) -> URL? {
        let categories = snippet.category.map { [$0] } ?? []
        return dittoImportLink(snippets: [snippet], categories: categories)
    }

    private func togglePin(_ snippet: Snippet) {
        // Just toggles the badge — pinning doesn't reorder the list, so
        // there's nothing to animate around the swipe dismissal.
        snippet.isPinned.toggle()
        try? modelContext.save()
    }

    private func delete(_ snippet: Snippet) {
        let title = snippet.displayTitle
        modelContext.delete(snippet)
        try? modelContext.save()
        deleteCount += 1
        withAnimation(.snappy) { deletedTitle = title }
    }

    private func duplicate(_ snippet: Snippet) {
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
        try? modelContext.save()
    }

    private func copy(_ snippet: Snippet) {
        UIPasteboard.general.string = snippet.content
        // Usage telemetry shouldn't land on the undo stack.
        let undo = modelContext.undoManager
        undo?.disableUndoRegistration()
        snippet.copyCount += 1
        snippet.lastCopiedAt = .now
        try? modelContext.save()
        undo?.enableUndoRegistration()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            copiedSnippetID = snippet.persistentModelID
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            // Only clear our own flash — a later copy may own the overlay now.
            guard copiedSnippetID == snippet.persistentModelID else { return }
            withAnimation(.easeOut(duration: 0.3)) { copiedSnippetID = nil }
        }
    }

    // MARK: - Grouping

    struct SnippetGroup: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let tint: Color
        let snippets: [Snippet]
    }

    /// Grouped layout applies only to All Snippets, when enabled, and not
    /// while searching (results are ranked, not filed).
    private var isGrouped: Bool {
        guard settings.grouping != .none, !isSearching else { return false }
        if case .all = selection { return true }
        return false
    }

    private var snippetGroups: [SnippetGroup] {
        switch settings.grouping {
        case .category:  return categoryGroups
        case .dateAdded: return dateGroups
        case .none:      return []
        }
    }

    /// Group by category, in category order, with uncategorized snippets last.
    private var categoryGroups: [SnippetGroup] {
        let snippets = filtered
        var seen = Set<PersistentIdentifier>()
        var orderedCats: [Category] = []
        for s in snippets {
            if let c = s.category, !seen.contains(c.persistentModelID) {
                seen.insert(c.persistentModelID)
                orderedCats.append(c)
            }
        }
        orderedCats.sort { $0.sortIndex < $1.sortIndex }

        var groups = orderedCats.map { c in
            SnippetGroup(id: "cat:\(c.name)", title: c.name, symbol: c.symbolName,
                         tint: SnippetColor.color(for: c.colorName),
                         snippets: snippets.filter { $0.category?.persistentModelID == c.persistentModelID })
        }
        let uncategorized = snippets.filter { $0.category == nil }
        if !uncategorized.isEmpty {
            groups.append(SnippetGroup(id: "uncategorized", title: "Uncategorized",
                                       symbol: "tray", tint: Color.secondary, snippets: uncategorized))
        }
        return groups
    }

    /// Group by date added, Finder-Recents style.
    private var dateGroups: [SnippetGroup] {
        let cal = Calendar.current
        let now = Date.now
        let startOfToday = cal.startOfDay(for: now)
        let startOfYesterday = cal.date(byAdding: .day, value: -1, to: startOfToday)!
        let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: startOfToday)!
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: startOfToday)!
        let startOfYear = cal.dateInterval(of: .year, for: now)?.start ?? startOfToday

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

        var byID: [String: (sort: Date, title: String, items: [Snippet])] = [:]
        for snippet in filtered {
            let b = bucket(for: snippet.createdAt)
            byID[b.id, default: (b.sort, b.title, [])].items.append(snippet)
        }
        return byID
            .sorted { $0.value.sort > $1.value.sort }
            .map { id, value in
                SnippetGroup(id: id, title: value.title, symbol: "calendar", tint: Color.secondary,
                             snippets: value.items.sorted { $0.createdAt > $1.createdAt })
            }
    }
}

struct SnippetRow: View {
    let snippet: Snippet
    let isCopied: Bool
    var showsCopyCount = false

    private var accent: Color {
        SnippetColor.color(for: snippet.category?.colorName ?? "blue")
    }

    var body: some View {
        content
            .opacity(isCopied ? 0 : 1)
            .overlay {
                if isCopied { CopiedOverlay(accent: accent) }
            }
    }

    /// The same colorful card recipe as the Mac app: accent gradient fill,
    /// hairline accent border, category icon up front.
    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: snippet.category?.symbolName ?? "doc.text")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(snippet.displayTitle)
                        .font(.body.weight(.semibold))
                        .fontDesign(.rounded)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if showsCopyCount {
                        Text("\(snippet.copyCount)×")
                            .font(.caption.weight(.bold))
                            .fontDesign(.rounded)
                            .monospacedDigit()
                            .foregroundStyle(accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(accent.opacity(0.15)))
                            .accessibilityLabel("Copied \(snippet.copyCount) times")
                    }
                    if snippet.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(accent.opacity(0.8))
                            .rotationEffect(.degrees(45))
                            .accessibilityLabel("Pinned")
                    }
                }
                Text(snippet.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Opaque base under the translucent gradient (as the Mac card does), so
        // cards occlude each other cleanly during reorder animations instead
        // of ghosting through one another.
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(
                    colors: [accent.opacity(0.16), accent.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(0.22), lineWidth: 1)
        )
    }
}

/// The copy confirmation: the card floods with its color and the Ditto mark
/// splits in two — one snippet, now also on your clipboard.
private struct CopiedOverlay: View {
    let accent: Color
    @State private var spread: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(accent.gradient)
            .overlay {
                HStack(spacing: 10) {
                    DittoGlyph(spread: spread)
                        .frame(width: 24, height: 24)
                    Text("Copied")
                        .font(.headline.weight(.bold))
                        .fontDesign(.rounded)
                }
                .foregroundStyle(.white)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.05)) {
                    spread = 1
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Copied")
    }
}

/// Long-press preview: the whole snippet, not just the two lines a card shows.
private struct SnippetPreview: View {
    let snippet: Snippet

    private var accent: Color {
        SnippetColor.color(for: snippet.category?.colorName ?? "blue")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: snippet.category?.symbolName ?? "doc.text")
                    .foregroundStyle(accent)
                Text(snippet.displayTitle)
                    .font(.headline)
                    .fontDesign(.rounded)
                    .lineLimit(1)
            }
            Text(snippet.content)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(18)
            HStack {
                if let category = snippet.category {
                    Text(category.name)
                }
                Spacer()
                Text("\(snippet.content.count) characters")
                    .monospacedDigit()
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 340)
        .background {
            LinearGradient(colors: [accent.opacity(0.14), accent.opacity(0.03)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
