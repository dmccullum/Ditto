//
//  CategoryEditor.swift
//  QuickCopy 2
//
//  Sheet for creating or editing a category: name, icon, and color.
//

import SwiftUI
import SwiftData

struct CategoryEditor: View {
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
        VStack(spacing: 0) {
            Form {
                Section("Name") {
                    HStack {
                        Image(systemName: symbolName)
                            .foregroundStyle(accent)
                            .frame(width: 24)
                        TextField(
                            text: $name,
                            prompt: Text("e.g. Hashtags").foregroundStyle(.secondary)
                        ) { EmptyView() }
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(SnippetColor.allCases) { swatch in
                            Circle()
                                .fill(swatch.color)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle().strokeBorder(.primary, lineWidth: colorName == swatch.rawValue ? 2.5 : 0)
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
                                .font(.system(size: 16))
                                .frame(width: 38, height: 38)
                                .foregroundStyle(symbolName == symbol ? .white : accent)
                                .background(symbolName == symbol ? accent : accent.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .onTapGesture { symbolName = symbol }
                        }
                    }
                    .padding(.vertical, 4)
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
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 560)
        .navigationTitle(isEditing ? "Edit Category" : "New Category")
        .onAppear(perform: loadInitialValues)
    }

    private func loadInitialValues() {
        guard let category else { return }
        name = category.name
        symbolName = category.symbolName
        colorName = category.colorName
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
            let newCategory = Category(name: trimmed, symbolName: symbolName, colorName: colorName, sortIndex: nextIndex)
            modelContext.insert(newCategory)
        }
        try? modelContext.save()
        dismiss()
    }
}
