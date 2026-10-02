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

                Section("Category") {
                    categoryPicker
                        .listRowInsets(EdgeInsets())
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

    /// Categories as the same colorful chips used to filter the library.
    private var categoryPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    categoryChoice(nil)
                    ForEach(categories) { category in
                        categoryChoice(category)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                if let id = selectedCategory?.persistentModelID {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func categoryChoice(_ category: Category?) -> some View {
        let isSelected = selectedCategory?.persistentModelID == category?.persistentModelID
        return Button {
            selectedCategory = category
        } label: {
            CategoryChip(title: category?.name ?? "None",
                         symbol: category?.symbolName ?? "tray",
                         tint: category.map { SnippetColor.color(for: $0.colorName) } ?? .gray,
                         isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .id(category?.persistentModelID)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

    private func deleteSnippet() {
        guard let snippet else { return }
        modelContext.delete(snippet)
        try? modelContext.save()
        dismiss()
    }
}
