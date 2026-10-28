//
//  SnippetCard.swift
//  Ditto
//
//  A colorful, clickable card. Clicking it copies the snippet to the clipboard
//  and briefly floods with its color while the Ditto mark splits in two.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SnippetCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.controlActiveState) private var controlActiveState
    let snippet: Snippet
    /// Card size level (0 = smallest … 4 = largest). The two smallest sizes
    /// use a more compact card so the blocks aren't needlessly tall.
    var sizeLevel: Int = 2
    /// Part of the grid's selection. The ring dims to gray when the grid
    /// isn't focused or the window isn't key, as Finder's does.
    var isSelected = false
    var isSelectionFocused = true
    /// Showing the copy confirmation.
    var isFlashing = false
    @Binding var isShowingPreview: Bool
    /// A drag from the grid is in progress (macOS 26's live reorder).
    var isDragging = false
    /// How many snippets the context menu acts on: the whole selection when
    /// this card is in it, otherwise just this card.
    var actionCount = 1
    var allTargetsPinned = false
    var onClick: () -> Void
    var onCopy: () -> Void
    var onEdit: () -> Void
    var onTogglePin: () -> Void
    var onDelete: () -> Void
    /// macOS 26 only: the drag passed over this card / was dropped on it.
    /// On 27 the grid's reorder container handles both.
    var onReorder: () -> Void
    var onCommit: () -> Void

    @State private var isHovering = false
    @State private var isHoveringPreviewButton = false

    private var accent: Color {
        SnippetColor.color(for: snippet.category?.colorName ?? "blue")
    }

    private var previewLineLimit: Int {
        switch sizeLevel {
        case 0:  return 1
        case 1:  return 2
        default: return 3
        }
    }

    private var cardMinHeight: CGFloat {
        switch sizeLevel {
        case 0:  return 68
        case 1:  return 82
        default: return 98
        }
    }

    private var cardPadding: CGFloat {
        sizeLevel <= 1 ? 11 : 14
    }

    private var selectionColor: Color {
        isSelectionFocused && controlActiveState == .key ? .accentColor : .secondary
    }

    var body: some View {
        Button(action: onClick) {
            content
                .frame(maxWidth: .infinity, minHeight: cardMinHeight, alignment: .topLeading)
                .padding(cardPadding)
                .background(cardBackground)
                .overlay {
                    if isFlashing { CopiedOverlay(accent: accent) }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accent.opacity(isHovering ? 0.55 : 0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(selectionColor, lineWidth: 3)
                            .padding(-4)
                    }
                }
                .shadow(color: accent.opacity(isHovering ? 0.25 : 0.08),
                        radius: isHovering ? 10 : 4, y: isHovering ? 5 : 2)
                .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        // The grid's drag container supplies the payload (and the rest of
        // the selection, when this card is selected).
        .draggable(containerItemID: snippet.persistentModelID)
        .modifier(LegacyReorderDrop(isDragging: isDragging, onReorder: onReorder,
                                    onCommit: onCommit))
        .contextMenu {
            let many = actionCount > 1
            Button(many ? "Copy \(actionCount) Snippets" : "Copy", systemImage: "doc.on.doc",
                   action: onCopy)
            if !many {
                Button("Preview", systemImage: "eye") { isShowingPreview = true }
                Button("Edit…", systemImage: "pencil", action: onEdit)
                Button("Duplicate", systemImage: "plus.square.on.square", action: duplicate)
                Button("Copy Share Link", systemImage: "link", action: copyShareLink)
            }
            Divider()
            Button(allTargetsPinned ? "Unpin" : "Pin",
                   systemImage: allTargetsPinned ? "pin.slash" : "pin",
                   action: onTogglePin)
            if !many, let url = snippet.urlValue {
                Button("Open Link", systemImage: "safari") {
                    NSWorkspace.shared.open(url)
                }
            }
            Divider()
            Button(many ? "Delete \(actionCount) Snippets" : "Delete", systemImage: "trash",
                   role: .destructive, action: onDelete)
        }
        .popover(isPresented: $isShowingPreview, arrowEdge: .bottom) {
            SnippetPreview(
                snippet: snippet,
                onCopy: { isShowingPreview = false; onCopy() },
                onEdit: { isShowingPreview = false; onEdit() }
            )
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: snippet.category?.symbolName ?? "doc.text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Text(snippet.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if snippet.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(accent.opacity(0.7))
                        .rotationEffect(.degrees(45))
                }
            }

            Text(snippet.preview)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(previewLineLimit)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                // Always-visible preview chip: eye + char count in one capsule,
                // brightening under the cursor so it reads as a button.
                Button { isShowingPreview = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                            .font(.caption2.weight(.semibold))
                        Text("\(snippet.content.count) chars")
                            .monospacedDigit()
                    }
                    // Never wrap the count ("2,87 / 5 / chars") on a narrow card.
                    .lineLimit(1)
                    .fixedSize()
                    // Quiet at rest; full accent once the card is hovered.
                    .foregroundStyle(accent.opacity(isHovering ? 1 : 0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(accent.opacity(
                            isHoveringPreviewButton ? 0.22 : (isHovering ? 0.10 : 0.06)
                        ))
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHoveringPreviewButton = $0 }
                .help("Preview the full snippet")
                Spacer(minLength: 4)
                // The hint drops to just its icon when the card is too narrow
                // for the label, rather than wrapping.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Click to copy")
                    }
                    .fixedSize()
                    Image(systemName: "doc.on.doc")
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(accent.opacity(isHovering ? 0.9 : 0.0))
        }
    }

    private var cardBackground: some View {
        LinearGradient(
            colors: [accent.opacity(0.16), accent.opacity(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .background(.background)
    }

    private func duplicate() {
        modelContext.insertUndoably(actionName: "Duplicate Snippet") {
            // Shift everything after the original down one slot so the copy's
            // position right after it is deterministic (no sortIndex ties).
            let all = (try? modelContext.fetch(FetchDescriptor<Snippet>())) ?? []
            for other in all where other.sortIndex > snippet.sortIndex {
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

    /// Copy a self-contained ditto://import link for this snippet (and its
    /// category, so the recipient files it correctly) to the clipboard.
    private func copyShareLink() {
        let categories = snippet.category.map { [$0] } ?? []
        if let link = dittoImportLink(snippets: [snippet], categories: categories) {
            Clipboard.copy(link.absoluteString)
        }
    }
}

/// The copy confirmation, shared with iOS: the card floods with its color and
/// the Ditto mark splits in two — one snippet, now also on your clipboard.
private struct CopiedOverlay: View {
    let accent: Color
    @State private var spread: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(accent.gradient)
            .overlay {
                HStack(spacing: 10) {
                    DittoGlyph(spread: spread)
                        .frame(width: 24, height: 24)
                    Text("Copied")
                        .font(.title3.weight(.bold))
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

/// A Quick Look-style popover showing a snippet's complete text — the card
/// itself truncates to a few lines. Text is selectable for partial copies.
private struct SnippetPreview: View {
    let snippet: Snippet
    var onCopy: () -> Void
    var onEdit: () -> Void

    private var accent: Color {
        SnippetColor.color(for: snippet.category?.colorName ?? "blue")
    }

    /// Long content scrolls inside a fixed height; short content hugs.
    private var isLong: Bool {
        snippet.content.count > 700 ||
        snippet.content.filter { $0 == "\n" }.count > 16
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: snippet.category?.symbolName ?? "doc.text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Text(snippet.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button("Edit…", action: onEdit)
                Button("Copy", action: onCopy)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)

            Divider()

            if isLong {
                ScrollView {
                    fullText
                }
                .frame(height: 380)
            } else {
                fullText
            }

            Divider()

            HStack {
                if let category = snippet.category {
                    Label(category.name, systemImage: category.symbolName)
                        .font(.caption)
                        .foregroundStyle(accent)
                }
                Spacer()
                Text("\(snippet.content.count) chars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(14)
        .frame(width: 400)
    }

    private var fullText: some View {
        Text(snippet.content)
            .font(.body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A dashed "+" tile shown at the end of a populated grid to add a snippet.
struct AddSnippetCard: View {
    var sizeLevel: Int = 2
    var action: () -> Void
    @State private var isHovering = false

    private var cardMinHeight: CGFloat {
        switch sizeLevel {
        case 0:  return 68
        case 1:  return 82
        default: return 98
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: sizeLevel == 0 ? 2 : 8) {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                Text("New Snippet")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: cardMinHeight)
            .padding(sizeLevel <= 1 ? 11 : 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.secondary.opacity(isHovering ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        .secondary.opacity(isHovering ? 0.6 : 0.3),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .help("Add a new snippet")
    }
}

/// What a dragged card carries: its identity, for drops inside Ditto (which
/// read the IDs from the drag session), and its text, for other apps.
nonisolated struct DraggedSnippet: Transferable {
    let id: PersistentIdentifier
    let content: String

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.content)
    }
}

/// macOS 26: reorders live as a drag passes over each card and commits on
/// drop. On 27, `reorderable()` and the grid's reorder container do this.
private struct LegacyReorderDrop: ViewModifier {
    let isDragging: Bool
    let onReorder: () -> Void
    let onCommit: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 27, *) {
            content
        } else {
            content.onDrop(of: [.text], delegate: SnippetReorderDropDelegate(
                isDragging: isDragging, onReorder: onReorder, onCommit: onCommit))
        }
    }
}

private struct SnippetReorderDropDelegate: DropDelegate {
    let isDragging: Bool
    let onReorder: () -> Void
    let onCommit: () -> Void

    func validateDrop(info: DropInfo) -> Bool { isDragging }

    func dropEntered(info: DropInfo) {
        if isDragging { onReorder() }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        onCommit()
        return true
    }
}
