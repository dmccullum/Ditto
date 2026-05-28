import SwiftUI
import SwiftData

struct CategoryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allCategories: [Category]

    var category: Category?

    @State private var name = ""
    @State private var symbolName = "tag.fill"
    @State private var colorName = "blue"

    private var isEditing: Bool { category != nil }
    private var accent: Color { SnippetColor.color(for: colorName) }
    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 8)]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    HStack {
                        Image(systemName: symbolName)
                            .foregroundStyle(accent)
                            .frame(width: 24)
                        TextField("e.g. Hashtags", text: $name)
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(SnippetColor.allCases) { swatch in
                            Circle()
                                .fill(swatch.color)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle().strokeBorder(.primary, lineWidth: colorName == swatch.rawValue ? 3 : 0)
                                )
                                .onTapGesture { colorName = swatch.rawValue }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Icon") {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(CategorySymbol.options, id: \.self) { symbol in
                            Image(systemName: symbol)
                                .font(.system(size: 18))
                                .frame(width: 44, height: 44)
                                .foregroundStyle(symbolName == symbol ? .white : accent)
                                .background(symbolName == symbol ? accent : accent.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .onTapGesture { symbolName = symbol }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(isEditing ? "Edit Category" : "New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                guard let category else { return }
                name = category.name
                symbolName = category.symbolName
                colorName = category.colorName
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let category {
            category.name = trimmed
            category.symbolName = symbolName
            category.colorName = colorName
        } else {
            let nextIndex = (allCategories.map(\.sortIndex).max() ?? -1) + 1
            modelContext.insert(Category(name: trimmed, symbolName: symbolName, colorName: colorName, sortIndex: nextIndex))
        }
        try? modelContext.save()
        dismiss()
    }
}
