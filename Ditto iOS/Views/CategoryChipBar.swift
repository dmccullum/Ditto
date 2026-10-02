//
//  CategoryChipBar.swift
//  DittoiOS
//
//  On iPhone the library is one screen: a sticky row of colorful filter chips
//  above the snippets, instead of a sidebar you have to back out of. Getting
//  from launch to a copied snippet is one tap, or two with a filter.
//

import SwiftUI
import SwiftData

/// A tinted capsule: soft tint when idle, filled with the tint when selected.
/// Used by the chip bar and the snippet editor's category picker.
struct CategoryChip: View {
    let title: String
    let symbol: String
    let tint: Color
    var count: Int? = nil
    var isSelected = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .imageScale(.medium)
            Text(title)
                .lineLimit(1)
            if let count {
                Text("\(count)")
                    .monospacedDigit()
                    .opacity(0.65)
            }
        }
        .font(.subheadline.weight(.semibold))
        .fontDesign(.rounded)
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(isSelected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.15)))
        }
        .overlay {
            Capsule().strokeBorder(tint.opacity(isSelected ? 0 : 0.22), lineWidth: 1)
        }
        .contentShape(Capsule())
    }
}

struct CategoryChipBar: View {
    @Binding var selection: SidebarSelection
    let categories: [Category]
    let allSnippets: [Snippet]
    var onNewCategory: () -> Void
    var onEdit: (Category) -> Void
    var onDuplicate: (Category) -> Void
    var onDelete: (Category) -> Void
    var onManage: () -> Void

    private var pinnedCount: Int { allSnippets.lazy.filter(\.isPinned).count }
    private var hasFrequent: Bool { allSnippets.contains { $0.copyCount > 0 } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip(.all, title: "All", symbol: "tray.full.fill", tint: .blue,
                         count: allSnippets.count)
                    if pinnedCount > 0 || selection == .pinned {
                        chip(.pinned, title: "Pinned", symbol: "pin.fill", tint: .orange,
                             count: pinnedCount)
                    }
                    if hasFrequent || selection == .frequent {
                        chip(.frequent, title: "Frequent", symbol: "flame.fill", tint: .red)
                    }

                    if !categories.isEmpty {
                        Divider()
                            .frame(height: 20)
                            .padding(.horizontal, 2)
                    }

                    ForEach(categories) { category in
                        categoryChip(category)
                    }

                    Button(action: onNewCategory) {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 34)
                            .overlay {
                                Capsule().strokeBorder(.secondary.opacity(0.5),
                                                       style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New Category")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, newValue in
                withAnimation(.snappy) { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func chip(_ value: SidebarSelection, title: String, symbol: String,
                      tint: Color, count: Int? = nil) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { selection = value }
        } label: {
            CategoryChip(title: title, symbol: symbol, tint: tint, count: count,
                         isSelected: selection == value)
        }
        .buttonStyle(.plain)
        .id(value)
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }

    private func categoryChip(_ category: Category) -> some View {
        chip(.category(category), title: category.name, symbol: category.symbolName,
             tint: SnippetColor.color(for: category.colorName), count: category.snippets.count)
            .contextMenu {
                Button { onEdit(category) } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button { onDuplicate(category) } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                if let link = dittoImportLink(snippets: category.snippets, categories: [category]) {
                    ShareLink(item: link) {
                        Label("Share Link", systemImage: "square.and.arrow.up")
                    }
                }
                Button(action: onManage) {
                    Label("Reorder Categories", systemImage: "arrow.up.arrow.down")
                }
                Divider()
                Button(role: .destructive) { onDelete(category) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}
