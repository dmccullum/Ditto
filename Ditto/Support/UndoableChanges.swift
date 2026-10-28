//
//  UndoableChanges.swift
//  Ditto
//
//  SwiftData can't reverse a delete once it has been saved: undo puts the
//  row back in the context, but the next save drops it again (or crashes).
//  Ditto saves after every change, so deleting — and redoing an insert,
//  which is the same thing in reverse — can't use SwiftData's own undo.
//  Instead, deletes snapshot the rows and register an undo that rebuilds
//  them (same UUIDs, so Spotlight and Shortcuts still match), and inserts
//  register an undo that runs that delete.
//
//  Edits, moves, and pins keep SwiftData's undo; those reverse fine.
//

import SwiftData
import Foundation

extension ModelContext {
    /// Deletes snippets and categories (a category takes its snippets with
    /// it) as one undoable step.
    func deleteUndoably(snippets: [Snippet] = [], categories: [Category] = [], actionName: String) {
        let snapshot = LibrarySnapshot(snippets: snippets, categories: categories)
        guard !snapshot.isEmpty else { return }
        withoutUndoRegistration {
            for category in categories { delete(category) }
            for snippet in snapshot.looseSnippets { delete(snippet) }
            try? save()
        }
        registerUndo(actionName) { $0.restore(snapshot, actionName: actionName) }
    }

    /// Runs `insert`, saves, and makes whatever snippets and categories it
    /// added one undoable step.
    func insertUndoably<T>(actionName: String, _ insert: () throws -> T) rethrows -> T {
        let before = libraryIDs()
        let result = try withoutUndoRegistration {
            let result = try insert()
            try? save()
            return result
        }
        let after = libraryIDs()
        let added = LibraryIDs(snippets: after.snippets.subtracting(before.snippets),
                               categories: after.categories.subtracting(before.categories))
        if !added.isEmpty {
            registerUndo(actionName) { $0.deleteUndoably(added, actionName: actionName) }
        }
        return result
    }

    /// Runs `body` without SwiftData recording it on the undo stack.
    func withoutUndoRegistration<T>(_ body: () throws -> T) rethrows -> T {
        undoManager?.disableUndoRegistration()
        defer { undoManager?.enableUndoRegistration() }
        return try body()
    }

    // MARK: - Private

    private func registerUndo(_ actionName: String, _ handler: @escaping (ModelContext) -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self, handler: handler)
        undoManager.setActionName(actionName)
    }

    private func deleteUndoably(_ ids: LibraryIDs, actionName: String) {
        let snippets = ((try? fetch(FetchDescriptor<Snippet>())) ?? [])
            .filter { $0.uuid.map(ids.snippets.contains) ?? false }
        let categories = ((try? fetch(FetchDescriptor<Category>())) ?? [])
            .filter { $0.uuid.map(ids.categories.contains) ?? false }
        deleteUndoably(snippets: snippets, categories: categories, actionName: actionName)
    }

    private func restore(_ snapshot: LibrarySnapshot, actionName: String) {
        let restored = withoutUndoRegistration {
            var restored = LibraryIDs()
            var categoriesByID: [UUID: Category] = [:]
            for existing in (try? fetch(FetchDescriptor<Category>())) ?? [] {
                if let id = existing.uuid { categoriesByID[id] = existing }
            }
            for saved in snapshot.categories {
                let category = saved.make()
                insert(category)
                if let id = category.uuid { categoriesByID[id] = category; restored.categories.insert(id) }
                for savedSnippet in saved.snippets {
                    insert(savedSnippet.make(category: category))
                }
            }
            for saved in snapshot.snippets {
                let snippet = saved.make(category: saved.categoryID.flatMap { categoriesByID[$0] })
                insert(snippet)
                if let id = snippet.uuid { restored.snippets.insert(id) }
            }
            try? save()
            return restored
        }
        registerUndo(actionName) { $0.deleteUndoably(restored, actionName: actionName) }
    }

    private func libraryIDs() -> LibraryIDs {
        LibraryIDs(snippets: Set(((try? fetch(FetchDescriptor<Snippet>())) ?? []).compactMap(\.uuid)),
                   categories: Set(((try? fetch(FetchDescriptor<Category>())) ?? []).compactMap(\.uuid)))
    }
}

private struct LibraryIDs {
    var snippets: Set<UUID> = []
    var categories: Set<UUID> = []
    var isEmpty: Bool { snippets.isEmpty && categories.isEmpty }
}

/// Plain values for deleted rows, enough to rebuild them exactly.
private struct LibrarySnapshot {
    struct SavedSnippet {
        let uuid: UUID?
        let title: String
        let content: String
        let sortIndex: Int
        let createdAt: Date
        let lastCopiedAt: Date?
        let copyCount: Int
        let isPinned: Bool
        let categoryID: UUID?

        init(_ snippet: Snippet) {
            uuid = snippet.uuid
            title = snippet.title
            content = snippet.content
            sortIndex = snippet.sortIndex
            createdAt = snippet.createdAt
            lastCopiedAt = snippet.lastCopiedAt
            copyCount = snippet.copyCount
            isPinned = snippet.isPinned
            categoryID = snippet.category?.uuid
        }

        func make(category: Category?) -> Snippet {
            let snippet = Snippet(title: title, content: content, sortIndex: sortIndex,
                                  isPinned: isPinned, category: category)
            snippet.uuid = uuid ?? snippet.uuid
            snippet.createdAt = createdAt
            snippet.lastCopiedAt = lastCopiedAt
            snippet.copyCount = copyCount
            return snippet
        }
    }

    struct SavedCategory {
        let uuid: UUID?
        let name: String
        let symbolName: String
        let colorName: String
        let sortIndex: Int
        let createdAt: Date
        let snippets: [SavedSnippet]

        init(_ category: Category) {
            uuid = category.uuid
            name = category.name
            symbolName = category.symbolName
            colorName = category.colorName
            sortIndex = category.sortIndex
            createdAt = category.createdAt
            snippets = category.snippets.map { SavedSnippet($0) }
        }

        func make() -> Category {
            let category = Category(name: name, symbolName: symbolName,
                                    colorName: colorName, sortIndex: sortIndex)
            category.uuid = uuid ?? category.uuid
            category.createdAt = createdAt
            return category
        }
    }

    let categories: [SavedCategory]
    /// Snippets deleted on their own, not along with their category.
    let snippets: [SavedSnippet]
    let looseSnippets: [Snippet]

    init(snippets: [Snippet], categories: [Category]) {
        let deletedCategories = Set(categories.map(\.persistentModelID))
        looseSnippets = snippets.filter {
            guard let category = $0.category else { return true }
            return !deletedCategories.contains(category.persistentModelID)
        }
        self.categories = categories.map { SavedCategory($0) }
        self.snippets = looseSnippets.map { SavedSnippet($0) }
    }

    var isEmpty: Bool { categories.isEmpty && snippets.isEmpty }
}
