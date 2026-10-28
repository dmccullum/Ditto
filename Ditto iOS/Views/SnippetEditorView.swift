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
    @State private var isConfirmingDelete = false
    @FocusState private var nameFocused: Bool

    private var isEditing: Bool { snippet != nil }
    private var isEmpty: Bool { content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The sheet takes on its category's color, so you can see where a
    /// snippet will live before you save it.
    private var accent: Color {
        selectedCategory.map { SnippetColor.color(for: $0.colorName) } ?? .blue
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Optional — e.g. Daily hashtags", text: $title)
                        .focused($nameFocused)
                        .submitLabel(.next)
                }

                Section {
                    TextEditor(text: $content)
                        .frame(minHeight: 140)
                } header: {
                    HStack {
                        Text("Content")
                        Spacer()
                        if isEmpty {
                            // The system Paste button reads the clipboard
                            // without the "allow paste" prompt.
                            PasteButton(payloadType: String.self) { strings in
                                guard let text = strings.first else { return }
                                content = text
                            }
                            .labelStyle(.titleAndIcon)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                        }
                    }
                } footer: {
                    HStack {
                        if let url = URL(string: content.trimmingCharacters(in: .whitespacesAndNewlines)),
                           url.scheme?.hasPrefix("http") == true, let host = url.host() {
                            Label(host, systemImage: "link")
                        }
                        Spacer()
                        Text(content.count == 1 ? "1 character" : "\(content.count) characters")
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .animation(.snappy, value: content.count)
                }

                Section {
                    categoryPicker
                }

                if isEditing {
                    Section {
                        Button("Delete Snippet", role: .destructive) {
                            isConfirmingDelete = true
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .tint(accent)
            .animation(.snappy, value: selectedCategory?.persistentModelID)
            .navigationTitle(isEditing ? "Edit Snippet" : "New Snippet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add", role: .confirm) { save() }
                        .disabled(isEmpty)
                }
            }
            .confirmationDialog("Delete this snippet?", isPresented: $isConfirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete Snippet", role: .destructive) { deleteSnippet() }
            }
            .sensoryFeedback(.selection, trigger: selectedCategory?.persistentModelID)
            .onAppear {
                if let snippet {
                    title = snippet.title
                    content = snippet.content
                    selectedCategory = snippet.category
                } else {
                    selectedCategory = defaultCategory
                    nameFocused = true
                }
            }
        }
    }

    /// A pushed list rather than a row of chips: it stays readable however
    /// many categories there are, and each row keeps its icon and color.
    private var categoryPicker: some View {
        Picker(selection: $selectedCategory) {
            categoryLabel(nil).tag(Category?.none)
            ForEach(categories) { category in
                categoryLabel(category).tag(Optional(category))
            }
        } label: {
            Text("Category")
        }
        .pickerStyle(.navigationLink)
    }

    private func categoryLabel(_ category: Category?) -> some View {
        Label {
            Text(category?.name ?? "None")
        } icon: {
            Image(systemName: category?.symbolName ?? "tray")
                .foregroundStyle(category.map { SnippetColor.color(for: $0.colorName) } ?? .gray)
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
            modelContext.insertUndoably(actionName: "New Snippet") {
                modelContext.insert(Snippet(title: title, content: content,
                                            sortIndex: Snippet.topSortIndex(in: modelContext),
                                            category: selectedCategory))
            }
        }
        try? modelContext.save()
        dismiss()
    }

    private func deleteSnippet() {
        guard let snippet else { return }
        modelContext.deleteUndoably(snippets: [snippet], actionName: "Delete Snippet")
        dismiss()
    }
}
