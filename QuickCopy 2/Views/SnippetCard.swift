//
//  SnippetCard.swift
//  QuickCopy 2
//
//  A colorful, clickable card. Clicking it copies the snippet to the clipboard
//  and briefly flips to a "Copied!" confirmation.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SnippetCard: View {
    @Environment(\.modelContext) private var modelContext
    let snippet: Snippet
    @Binding var draggedSnippet: Snippet?
    var onEdit: () -> Void
    var onReorder: (_ dragged: Snippet, _ target: Snippet) -> Void
    var onCommit: () -> Void

    @State private var didCopy = false
    @State private var isHovering = false

    private var accent: Color {
        SnippetColor.color(for: snippet.category?.colorName ?? "blue")
    }

    var body: some View {
        Button(action: copy) {
            ZStack(alignment: .topLeading) {
                content
                if didCopy { copiedOverlay }
            }
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .padding(14)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(accent.opacity(isHovering ? 0.55 : 0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: accent.opacity(isHovering ? 0.25 : 0.08),
                    radius: isHovering ? 10 : 4, y: isHovering ? 5 : 2)
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .onDrag {
            draggedSnippet = snippet
            // Provide plain text so the snippet can also be dragged into other apps.
            return NSItemProvider(object: snippet.content as NSString)
        }
        .onDrop(
            of: [.text],
            delegate: SnippetReorderDropDelegate(
                target: snippet,
                draggedSnippet: $draggedSnippet,
                onReorder: onReorder,
                onCommit: onCommit
            )
        )
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc", action: copy)
            Button("Edit…", systemImage: "pencil", action: onEdit)
            Button("Duplicate", systemImage: "plus.square.on.square", action: duplicate)
            Divider()
            Button(snippet.isPinned ? "Unpin" : "Pin",
                   systemImage: snippet.isPinned ? "pin.slash" : "pin",
                   action: togglePin)
            if let url = snippet.urlValue {
                Button("Open Link", systemImage: "safari") {
                    NSWorkspace.shared.open(url)
                }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
        }
        .help("Click to copy · drag to reorder, into a category, or out to another app")
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
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Text("\(snippet.content.count) chars")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Image(systemName: "doc.on.doc")
                Text("Click to copy")
                    .foregroundStyle(accent.opacity(isHovering ? 0.9 : 0.0))
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

    private var copiedOverlay: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(accent.opacity(0.92))
            .overlay(
                Label("Copied!", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            )
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private func copy() {
        Clipboard.copy(snippet.content)
        snippet.copyCount += 1
        snippet.lastCopiedAt = .now
        try? modelContext.save()

        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { didCopy = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeOut(duration: 0.25)) { didCopy = false }
        }
    }

    private func duplicate() {
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

    private func togglePin() {
        snippet.isPinned.toggle()
        try? modelContext.save()
    }

    private func delete() {
        modelContext.delete(snippet)
        try? modelContext.save()
    }
}

/// A dashed "+" tile shown at the end of a populated grid to add a snippet.
struct AddSnippetCard: View {
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                Text("New Snippet")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 110)
            .padding(14)
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

/// Reorders snippets live as one is dragged over another. We don't decode the
/// dragged payload here — instead we read the shared `draggedSnippet` that was
/// set when the drag began, which is far more reliable for in-app reordering.
struct SnippetReorderDropDelegate: DropDelegate {
    let target: Snippet
    @Binding var draggedSnippet: Snippet?
    let onReorder: (_ dragged: Snippet, _ target: Snippet) -> Void
    let onCommit: () -> Void

    func validateDrop(info: DropInfo) -> Bool { draggedSnippet != nil }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedSnippet,
              dragged.persistentModelID != target.persistentModelID else { return }
        onReorder(dragged, target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        onCommit()
        return true
    }
}
