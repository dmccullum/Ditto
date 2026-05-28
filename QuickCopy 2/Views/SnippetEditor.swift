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

    @State private var title = ""
    @State private var content = ""
    @State private var selectedCategory: Category?

    private var isEditing: Bool { snippet != nil }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Name (optional)") {
                    TextField("e.g. Daily content tags", text: $title)
                }
                Section("Content") {
                    TextEditor(text: $content)
                        .font(.body)
                        .frame(minHeight: 140)
                }
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        Text("None").tag(Category?.none)
                        ForEach(categories) { category in
                            Label(category.name, systemImage: category.symbolName)
                                .tag(Category?.some(category))
                        }
                    }
                    .labelsHidden()
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: 460, height: 420)
        .navigationTitle(isEditing ? "Edit Snippet" : "New Snippet")
        .onAppear(perform: loadInitialValues)
    }

    private func loadInitialValues() {
        if let snippet {
            title = snippet.title
            content = snippet.content
            selectedCategory = snippet.category
        } else {
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
