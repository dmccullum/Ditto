import SwiftUI
import SwiftData

struct CategoryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortIndex) private var allCategories: [Category]

    var category: Category?

    @State private var name = ""
    @State private var symbolName = "tag.fill"
    @State private var colorName = "blue"
    @State private var isConfirmingDelete: Category?
    @FocusState private var nameFocused: Bool

    private var isEditing: Bool { category != nil }
    private var accent: Color { SnippetColor.color(for: colorName) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 10)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }

                Section("Name") {
                    TextField("e.g. Hashtags", text: $name)
                        .focused($nameFocused)
                        .submitLabel(.done)
                }

                Section("Color") {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(SnippetColor.allCases) { swatch in
                            colorSwatch(swatch)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Icon") {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(CategorySymbol.options, id: \.self) { symbol in
                            symbolTile(symbol)
                        }
                    }
                    .padding(.vertical, 6)
                }

                if let category {
                    Section {
                        Button("Delete Category", role: .destructive) {
                            isConfirmingDelete = category
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .tint(accent)
            .navigationTitle(isEditing ? "Edit Category" : "New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add", role: .confirm) { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .confirmDeletion(of: $isConfirmingDelete) { target in
                modelContext.deleteUndoably(categories: [target], actionName: "Delete Category")
                dismiss()
            }
            .sensoryFeedback(.selection, trigger: colorName)
            .sensoryFeedback(.selection, trigger: symbolName)
            .onAppear {
                if let category {
                    name = category.name
                    symbolName = category.symbolName
                    colorName = category.colorName
                } else {
                    colorName = freshColor
                    nameFocused = true
                }
            }
        }
    }

    /// What the category will look like in the library, updating live.
    private var preview: some View {
        VStack(spacing: 14) {
            Image(systemName: symbolName)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(accent.gradient))
                .shadow(color: accent.opacity(0.35), radius: 12, y: 6)
            CategoryChip(title: trimmedName.isEmpty ? "New Category" : trimmedName,
                         symbol: symbolName, tint: accent, isSelected: true)
        }
        .padding(.top, 8)
        .animation(.snappy, value: colorName)
        .animation(.snappy, value: symbolName)
        .accessibilityHidden(true)
    }

    private func colorSwatch(_ swatch: SnippetColor) -> some View {
        let isSelected = colorName == swatch.rawValue
        return Button { colorName = swatch.rawValue } label: {
            Circle()
                .fill(swatch.color.gradient)
                .frame(width: 34, height: 34)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.heavy))
                            .foregroundStyle(.white)
                    }
                }
                .padding(4)
                .overlay {
                    Circle().strokeBorder(swatch.color, lineWidth: isSelected ? 2 : 0)
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(swatch.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func symbolTile(_ symbol: String) -> some View {
        let isSelected = symbolName == symbol
        return Button { symbolName = symbol } label: {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .frame(width: 44, height: 44)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(accent))
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(accent.opacity(0.12)))
                )
                .contentShape(.rect(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol.replacingOccurrences(of: ".fill", with: "")
            .replacingOccurrences(of: ".", with: " "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// New categories start on a color the library isn't using yet, so a
    /// fresh category looks fresh instead of yet another blue.
    private var freshColor: String {
        let used = Set(allCategories.map(\.colorName))
        let preferred: [SnippetColor] = [.blue, .orange, .green, .purple, .pink, .teal,
                                         .indigo, .red, .mint, .gold, .cyan, .rose]
        return (preferred.first { !used.contains($0.rawValue) } ?? .blue).rawValue
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        if let category {
            category.name = trimmedName
            category.symbolName = symbolName
            category.colorName = colorName
        } else {
            let nextIndex = (allCategories.map(\.sortIndex).max() ?? -1) + 1
            modelContext.insertUndoably(actionName: "New Category") {
                modelContext.insert(Category(name: trimmedName, symbolName: symbolName,
                                             colorName: colorName, sortIndex: nextIndex))
            }
        }
        try? modelContext.save()
        dismiss()
    }
}
