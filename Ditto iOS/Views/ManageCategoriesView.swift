//
//  ManageCategoriesView.swift
//  DittoiOS
//
//  Reorder, edit, and delete categories in one place. Reached from the
//  library's More menu, a chip's context menu, or Settings.
//

import SwiftUI
import SwiftData

struct ManageCategoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    /// Presented as its own sheet (needs a Done button) vs pushed from Settings.
    var isModal = false

    @State private var editingCategory: Category?
    @State private var deletingCategory: Category?
    @State private var isCreatingCategory = false

    var body: some View {
        List {
            Section {
                ForEach(categories) { category in
                    Button { editingCategory = category } label: {
                        row(category)
                    }
                    .foregroundStyle(.primary)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { deletingCategory = category } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: move)
            } footer: {
                if categories.count > 1 {
                    Text("Touch and hold a category, then drag to reorder. The library's chips follow this order.")
                }
            }

            Section {
                Button { isCreatingCategory = true } label: {
                    Label("New Category", systemImage: "plus.circle.fill")
                }
            }
        }
        .overlay {
            if categories.isEmpty {
                ContentUnavailableView("No Categories", systemImage: "folder",
                    description: Text("Categories give your snippets a color and a home."))
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isModal {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
            }
        }
        .sheet(item: $editingCategory) { CategoryEditorView(category: $0) }
        .sheet(isPresented: $isCreatingCategory) { CategoryEditorView() }
        .confirmDeletion(of: $deletingCategory) { category in
            modelContext.delete(category)
            try? modelContext.save()
        }
    }

    private func row(_ category: Category) -> some View {
        let tint = SnippetColor.color(for: category.colorName)
        return HStack(spacing: 12) {
            Image(systemName: category.symbolName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.gradient))
            Text(category.name)
            Spacer()
            Text("\(category.snippets.count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edits the category")
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = categories
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in ordered.enumerated() where category.sortIndex != index {
            category.sortIndex = index
        }
        try? modelContext.save()
    }
}
