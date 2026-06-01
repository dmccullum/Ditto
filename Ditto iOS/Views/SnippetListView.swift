import SwiftUI
import SwiftData

struct SnippetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings

    let selection: SidebarSelection
    let searchText: String
    let allSnippets: [Snippet]

    @State private var editingSnippet: Snippet?
    @State private var copiedSnippetID: PersistentIdentifier?
    @State private var collapsedGroups: Set<String> = []

    private var filtered: [Snippet] {
        let base: [Snippet]
        switch selection {
        case .all:
            base = allSnippets.sorted { $0.isPinned && !$1.isPinned }
        case .pinned:
            base = allSnippets.filter { $0.isPinned }
        case .category(let cat):
            base = allSnippets.filter { $0.category?.persistentModelID == cat.persistentModelID }
                .sorted { $0.isPinned && !$1.isPinned }
        }
        guard !searchText.isEmpty else { return base }
        let q = searchText.lowercased()
        return base.filter {
            $0.displayTitle.lowercased().contains(q) ||
            $0.content.lowercased().contains(q)
        }
    }

    var body: some View {
        Group {
            if filtered.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Snippets" : "No Results",
                    systemImage: searchText.isEmpty ? "doc.on.doc" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? "Tap + to add your first snippet."
                        : "Try a different search term.")
                )
            } else if isGrouped {
                groupedList
            } else {
                flatList
            }
        }
        .sheet(item: $editingSnippet) { SnippetEditorView(snippet: $0) }
    }

    private var flatList: some View {
        List {
            ForEach(filtered) { snippet in rowView(snippet) }
                .onMove(perform: moveSnippets)
        }
        .listStyle(.plain)
    }

    /// Reorder snippets (Edit mode), persisting the new order as sortIndex.
    private func moveSnippets(from source: IndexSet, to destination: Int) {
        var items = filtered
        items.move(fromOffsets: source, toOffset: destination)
        for (index, snippet) in items.enumerated() {
            snippet.sortIndex = index
        }
        try? modelContext.save()
    }

    private var groupedList: some View {
        List {
            ForEach(snippetGroups) { group in
                Section {
                    if !collapsedGroups.contains(group.id) {
                        ForEach(group.snippets) { snippet in rowView(snippet) }
                    }
                } header: {
                    groupHeader(group)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func rowView(_ snippet: Snippet) -> some View {
        SnippetRow(snippet: snippet, isCopied: copiedSnippetID == snippet.persistentModelID)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .contentShape(Rectangle())
            .onTapGesture { copy(snippet) }
            .swipeActions(edge: .leading) {
                Button {
                    snippet.isPinned.toggle()
                    try? modelContext.save()
                } label: {
                    Label(snippet.isPinned ? "Unpin" : "Pin",
                          systemImage: snippet.isPinned ? "pin.slash" : "pin")
                }
                .tint(.orange)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    modelContext.delete(snippet)
                } label: { Label("Delete", systemImage: "trash") }
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
                Button {
                    snippet.isPinned.toggle()
                    try? modelContext.save()
                } label: {
                    Label(snippet.isPinned ? "Unpin" : "Pin",
                          systemImage: snippet.isPinned ? "pin.slash" : "pin")
                }
                if let url = snippet.urlValue {
                    Button { UIApplication.shared.open(url) } label: {
                        Label("Open Link", systemImage: "safari")
                    }
                }
                if let link = shareLink(for: snippet) {
                    ShareLink(item: link) {
                        Label("Share Link", systemImage: "square.and.arrow.up")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    modelContext.delete(snippet)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    private func groupHeader(_ group: SnippetGroup) -> some View {
        let collapsed = collapsedGroups.contains(group.id)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if collapsed { collapsedGroups.remove(group.id) }
                else { collapsedGroups.insert(group.id) }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                Image(systemName: group.symbol)
                    .foregroundStyle(group.tint)
                Text(group.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(group.snippets.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
    }

    /// A self-contained ditto://import link for this snippet (and its category).
    private func shareLink(for snippet: Snippet) -> URL? {
        let categories = snippet.category.map { [$0] } ?? []
        return dittoImportLink(snippets: [snippet], categories: categories)
    }

    private func duplicate(_ snippet: Snippet) {
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

        withAnimation {
            copiedSnippetID = snippet.persistentModelID
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copiedSnippetID = nil }
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

    private var isAllSelection: Bool {
        if case .all = selection { return true }
        return false
    }

    /// Grouped layout applies only to All Snippets, when enabled.
    private var isGrouped: Bool {
        settings.grouping != .none && isAllSelection
    }

    private var snippetGroups: [SnippetGroup] {
        switch settings.grouping {
        case .category:  return categoryGroups
        case .dateAdded: return dateGroups
        case .none:      return []
        }
    }

    /// Group by category, in sidebar order, with uncategorized snippets last.
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

    private var accent: Color {
        SnippetColor.color(for: snippet.category?.colorName ?? "blue")
    }

    var body: some View {
        ZStack {
            content
                .opacity(isCopied ? 0 : 1)
            if isCopied {
                copiedOverlay
            }
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if snippet.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(snippet.displayTitle)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                }
                Text(snippet.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let cat = snippet.category {
                    Label(cat.name, systemImage: cat.symbolName)
                        .font(.caption)
                        .foregroundStyle(SnippetColor.color(for: cat.colorName))
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var copiedOverlay: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(accent)
            .overlay(
                Label("Copied!", systemImage: "checkmark.circle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            )
            .frame(maxWidth: .infinity)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}
