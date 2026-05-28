//
//  SnippetEditor.swift
//  QuickCopy 2
//
//  Sheet for creating or editing a snippet. Handles both cases: pass an
//  existing snippet to edit it, or nil to create a new one.
//

import SwiftUI
import SwiftData

struct SnippetEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    /// The snippet being edited, or nil when creating a new one.
    var snippet: Snippet?
    /// Pre-selected category when creating from within a category.
    var defaultCategory: Category?
    /// Pre-filled content (e.g. when creating from a paste).
    var defaultContent: String = ""

    @State private var title = ""
    @State private var content = ""
    @State private var selectedCategory: Category?

    private enum Field { case content, name }
    @FocusState private var focus: Field?

    private var isEditing: Bool { snippet != nil }

    private var isEmpty: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(isEditing ? "Edit Snippet" : "New Snippet")
                .font(.title2.bold())

            field("Content", trailing: "\(content.count) characters") {
                TextEditor(text: $content)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(height: 150)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.quaternary)
                    )
                    .focused($focus, equals: .content)
            }

            field("Name (optional)") {
                TextField("e.g. Daily content tags", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .name)
            }

            field("Category") {
                Picker("Category", selection: $selectedCategory) {
                    Text("None").tag(Category?.none)
                    ForEach(categories) { category in
                        Label(category.name, systemImage: category.symbolName)
                            .tag(Category?.some(category))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460, height: 470)
        .onAppear {
            loadInitialValues()
            // Pasted/new snippets land cursor sensibly: empty content -> Content,
            // pre-filled content (e.g. from paste) -> Name.
            DispatchQueue.main.async {
                focus = content.isEmpty ? .content : .name
            }
        }
    }

    /// A left-aligned labelled field, optional trailing label (e.g. char count).
    @ViewBuilder
    private func field<Content: View>(
        _ label: String,
        trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            content()
        }
    }

    private func loadInitialValues() {
        if let snippet {
            title = snippet.title
            content = snippet.content
            selectedCategory = snippet.category
        } else {
            content = defaultContent
            selectedCategory = defaultCategory
        }
    }

    private func save() {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }

        if let snippet {
            snippet.title = title
            snippet.content = content
            snippet.category = selectedCategory
        } else {
            let newSnippet = Snippet(title: title, content: content, category: selectedCategory)
            modelContext.insert(newSnippet)
        }
        try? modelContext.save()
        dismiss()
    }
}
