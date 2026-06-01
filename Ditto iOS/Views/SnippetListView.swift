import SwiftUI
import SwiftData

struct SnippetListView: View {
    @Environment(\.modelContext) private var modelContext

    let selection: SidebarSelection
    let searchText: String
    let allSnippets: [Snippet]

    @State private var editingSnippet: Snippet?
    @State private var copiedSnippetID: PersistentIdentifier?

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
            } else {
                List {
                    ForEach(filtered) { snippet in
                        SnippetRow(snippet: snippet, isCopied: copiedSnippetID == snippet.persistentModelID)
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                            .contentShape(Rectangle())
                            .onTapGesture { copy(snippet) }
                            .swipeActions(edge: .leading) {
                                Button { copy(snippet) } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    modelContext.delete(snippet)
                                } label: { Label("Delete", systemImage: "trash") }
                                Button { editingSnippet = snippet } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.orange)
                                Button {
                                    snippet.isPinned.toggle()
                                    try? modelContext.save()
                                } label: {
                                    Label(snippet.isPinned ? "Unpin" : "Pin",
                                          systemImage: snippet.isPinned ? "pin.slash" : "pin")
                                }
                                .tint(.indigo)
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
                                Divider()
                                Button(role: .destructive) {
                                    modelContext.delete(snippet)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(item: $editingSnippet) { SnippetEditorView(snippet: $0) }
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
}

struct SnippetRow: View {
    let snippet: Snippet
    let isCopied: Bool

    var body: some View {
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
            Spacer()
            if isCopied {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}
