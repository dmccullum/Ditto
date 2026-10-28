//
//  DittoIntents.swift
//  DittoiOS
//
//  App Intents: exposes snippets to Siri, Shortcuts, Spotlight, and the
//  Action button. The headline is CopySnippetIntent — copy any snippet to
//  the clipboard without ever opening the app.
//

import AppIntents
import SwiftData
import CoreSpotlight
import UIKit

// MARK: - Store access

/// Fetch helpers shared by the intents and entity queries. Everything goes
/// through DittoStore.container, the same database the app UI uses.
@MainActor
enum DittoIntents {
    static var context: ModelContext { DittoStore.container.mainContext }

    static func allSnippets() throws -> [Snippet] {
        try context.fetch(FetchDescriptor<Snippet>(sortBy: [SortDescriptor(\Snippet.sortIndex)]))
    }

    static func allCategories() throws -> [Category] {
        try context.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\Category.sortIndex)]))
    }

    static func snippets(with identifiers: [UUID]) throws -> [Snippet] {
        let wanted = Set(identifiers)
        return try allSnippets().filter { snippet in
            guard let uuid = snippet.uuid else { return false }
            return wanted.contains(uuid)
        }
    }

    static func snippet(for id: UUID) throws -> Snippet? {
        try snippets(with: [id]).first
    }

    /// Copy snippet text and record usage, exactly like a tap in the app.
    static func copyToClipboard(_ snippet: Snippet) {
        UIPasteboard.general.string = snippet.content
        // Usage telemetry shouldn't land on the undo stack.
        let undo = context.undoManager
        undo?.disableUndoRegistration()
        snippet.copyCount += 1
        snippet.lastCopiedAt = .now
        try? context.save()
        undo?.enableUndoRegistration()
    }
}

// MARK: - Entities

struct SnippetEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Snippet"
    static let defaultQuery = SnippetEntityQuery()

    let id: UUID
    let title: String
    let preview: String
    let categoryName: String?

    @MainActor
    init(_ snippet: Snippet) {
        self.id = snippet.uuid ?? UUID()
        self.title = snippet.displayTitle
        self.preview = snippet.preview
        self.categoryName = snippet.category?.name
    }

    var displayRepresentation: DisplayRepresentation {
        // When a snippet has no name, the title already shows its first line —
        // repeating the content as a subtitle would just be noise.
        let subtitle: LocalizedStringResource? =
            (preview.isEmpty || preview == title) ? nil : "\(preview)"
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: subtitle,
            image: .init(systemName: "doc.on.doc")
        )
    }

    /// What Spotlight indexes for this snippet.
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title
        attributes.contentDescription = preview
        attributes.keywords = [categoryName, "snippet"].compactMap(\.self)
        return attributes
    }
}

struct SnippetEntityQuery: EntityQuery, EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [SnippetEntity] {
        try DittoIntents.snippets(with: identifiers).map(SnippetEntity.init)
    }

    /// What the snippet picker offers before the user types: pinned and
    /// frequently used first, mirroring the app's own priorities.
    @MainActor
    func suggestedEntities() async throws -> [SnippetEntity] {
        let ranked = try DittoIntents.allSnippets().sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.copyCount != $1.copyCount { return $0.copyCount > $1.copyCount }
            return $0.sortIndex < $1.sortIndex
        }
        return ranked.prefix(12).map(SnippetEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [SnippetEntity] {
        try DittoIntents.allSnippets()
            .filter {
                $0.displayTitle.localizedStandardContains(string) ||
                $0.content.localizedStandardContains(string)
            }
            .map(SnippetEntity.init)
    }
}

struct CategoryEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static let defaultQuery = CategoryEntityQuery()

    let id: UUID
    let name: String
    let symbolName: String

    @MainActor
    init(_ category: Category) {
        self.id = category.uuid ?? UUID()
        self.name = category.name
        self.symbolName = category.symbolName
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbolName))
    }
}

struct CategoryEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [CategoryEntity] {
        let wanted = Set(identifiers)
        return try DittoIntents.allCategories()
            .filter { category in category.uuid.map(wanted.contains) ?? false }
            .map(CategoryEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [CategoryEntity] {
        try DittoIntents.allCategories().map(CategoryEntity.init)
    }
}

// MARK: - Intents

struct CopySnippetIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Snippet"
    static let description = IntentDescription(
        "Copies a snippet's text to the clipboard.",
        categoryName: "Snippets",
        searchKeywords: ["paste", "clipboard", "copy", "snippet"]
    )

    @Parameter(title: "Snippet")
    var snippet: SnippetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Copy \(\.$snippet)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let model = try DittoIntents.snippet(for: snippet.id) else {
            throw DittoIntentError.snippetNotFound
        }
        DittoIntents.copyToClipboard(model)
        // Also return the text so the intent chains in Shortcuts workflows.
        return .result(value: model.content, dialog: "Copied “\(model.displayTitle)”.")
    }
}

struct CreateSnippetIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Snippet"
    static let description = IntentDescription(
        "Saves new snippet text to your Ditto library.",
        categoryName: "Snippets",
        searchKeywords: ["new", "add", "save", "snippet"]
    )

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @Parameter(title: "Name")
    var name: String?

    @Parameter(title: "Category")
    var category: CategoryEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$text) as a snippet") {
            \.$name
            \.$category
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<SnippetEntity> & ProvidesDialog {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DittoIntentError.emptyContent
        }
        let category = try category.flatMap { picked in
            try DittoIntents.allCategories().first { $0.uuid == picked.id }
        }
        let snippet = Snippet(title: name ?? "", content: text,
                              sortIndex: Snippet.topSortIndex(in: DittoIntents.context),
                              category: category)
        // Kept off the app's undo stack: shaking to undo shouldn't remove
        // something saved from Siri or Shortcuts.
        try DittoIntents.context.withoutUndoRegistration {
            DittoIntents.context.insert(snippet)
            try DittoIntents.context.save()
        }
        await DittoSpotlight.refresh()
        return .result(value: SnippetEntity(snippet), dialog: "Saved “\(snippet.displayTitle)”.")
    }
}

enum DittoIntentError: Error, CustomLocalizedStringResourceConvertible {
    case snippetNotFound
    case emptyContent

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .snippetNotFound: "That snippet no longer exists."
        case .emptyContent:    "The snippet text is empty."
        }
    }
}

// MARK: - App Shortcuts (zero-setup Siri/Spotlight phrases)

struct DittoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CopySnippetIntent(),
            phrases: [
                "Copy \(\.$snippet) in \(.applicationName)",
                "Copy a \(.applicationName) snippet",
                "Copy a snippet from \(.applicationName)"
            ],
            shortTitle: "Copy Snippet",
            systemImageName: "doc.on.doc"
        )
        AppShortcut(
            intent: CreateSnippetIntent(),
            phrases: [
                "Create a snippet in \(.applicationName)",
                "Add a snippet to \(.applicationName)",
                "Save a snippet in \(.applicationName)"
            ],
            shortTitle: "New Snippet",
            systemImageName: "square.and.pencil"
        )
    }
}

// MARK: - Spotlight

enum DittoSpotlight {
    /// Re-donate the whole library to Spotlight. Delete-then-index keeps
    /// removed snippets out, and a full pass is cheap at personal-library
    /// scale. Runs at launch and after intent-driven creates; in-app edits
    /// are picked up on the next launch.
    @MainActor
    static func refresh() async {
        guard !DittoStore.isDemo else { return }
        guard let snippets = try? DittoIntents.allSnippets() else { return }
        let index = CSSearchableIndex.default()
        try? await index.deleteAllSearchableItems()
        try? await index.indexAppEntities(snippets.map(SnippetEntity.init))
    }
}
