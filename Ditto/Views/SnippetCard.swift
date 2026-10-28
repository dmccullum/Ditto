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
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.colorSchemeContrast) private var contrast
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
    var onDuplicate: () -> Void
    var onCopyShareLink: () -> Void
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

    /// The card's outline, raised under Increase Contrast.
    private var strokeOpacity: Double {
        switch (contrast == .increased, isHovering) {
        case (false, false): 0.18
        case (false, true):  0.55
        case (true, false):  0.6
        case (true, true):   0.9
        }
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
                        .strokeBorder(accent.opacity(strokeOpacity), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(selectionColor, lineWidth: 3)
                            .padding(-4)
                    }
                }
                // Hover changes the outline and footer tint only; the card
                // doesn't grow or lift.
                .shadow(color: accent.opacity(0.08), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
        .animation(.snappy(duration: 0.2), value: isHovering)
        // The grid's drag container supplies the payload (and the rest of
        // the selection, when this card is selected).
        .draggable(containerItemID: snippet.persistentModelID)
        .modifier(LegacyReorderDrop(isDragging: isDragging, onReorder: onReorder,
                                    onCommit: onCommit))
        // Same commands, in the same order, as the Snippet menu.
        .contextMenu {
            let many = actionCount > 1
            Button(many ? "Copy \(actionCount) Snippets" : "Copy", action: onCopy)
            if !many {
                if let url = snippet.urlValue {
                    Button("Open Link") { NSWorkspace.shared.open(url) }
                }
                Button("Preview") { isShowingPreview = true }
            }
            Divider()
            if !many {
                Button("Edit…", action: onEdit)
                Button("Duplicate", action: onDuplicate)
            }
            Button(allTargetsPinned ? "Unpin" : "Pin", action: onTogglePin)
            if !many {
                Divider()
                Button("Copy Share Link", action: onCopyShareLink)
            }
            Divider()
            Button(many ? "Delete \(actionCount) Snippets" : "Delete", role: .destructive,
                   action: onDelete)
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
}

/// The copy confirmation, shared with iOS: the card floods with its color and
/// the Ditto mark splits in two — one snippet, now also on your clipboard.
private struct CopiedOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            .onAppear {
                // Reduce Motion shows the mark already split; the fade is enough.
                if reduceMotion {
                    spread = 1
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.05)) {
                        spread = 1
                    }
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
    @Environment(\.colorSchemeContrast) private var contrast
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
                        .secondary.opacity(contrast == .increased
                                           ? (isHovering ? 0.9 : 0.6)
                                           : (isHovering ? 0.6 : 0.3)),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.snappy(duration: 0.2), value: isHovering)
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
