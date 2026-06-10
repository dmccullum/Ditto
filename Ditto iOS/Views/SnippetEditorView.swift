import SwiftUI
import SwiftData

struct SnippetEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    var snippet: Snippet?
    var defaultCategory: Category?

    @State private var title = ""
    @State private var content = ""
    @State private var selectedCategory: Category?
    @FocusState private var contentFocused: Bool

    private var isEditing: Bool { snippet != nil }
    private var isEmpty: Bool { content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Content") {
                    TextEditor(text: $content)
                        .frame(minHeight: 120)
                        .focused($contentFocused)
                }

                Section("Name (optional)") {
                    TextField("e.g. Daily hashtags", text: $title)
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        Text("None").tag(Category?.none)
                        ForEach(categories) { cat in
                            Label(cat.name, systemImage: cat.symbolName)
                                .tag(Category?.some(cat))
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Snippet" : "New Snippet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .disabled(isEmpty)
                }
            }
            .onAppear {
                if let snippet {
                    title = snippet.title
                    content = snippet.content
                    selectedCategory = snippet.category
                } else {
                    selectedCategory = defaultCategory
                    contentFocused = true
                }
            }
        }
    }

    private func save() {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let snippet {
            snippet.title = title
            snippet.content = content
            snippet.category = selectedCategory
        } else {
            modelContext.insert(Snippet(title: title, content: content,
                                        sortIndex: Snippet.topSortIndex(in: modelContext),
                                        category: selectedCategory))
        }
        try? modelContext.save()
        dismiss()
    }
}
