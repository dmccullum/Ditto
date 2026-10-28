//
//  WidgetStore.swift
//  Ditto Widgets
//
//  The widget extension's view of the app's database: the same SwiftData
//  store, opened from the App Group container. Unlike the app's DittoStore
//  it never creates, seeds, or migrates the store — until the app has run
//  once there is nothing to show.
//

import Foundation
import SwiftData

/// A snippet flattened for widget timelines, which must be value types.
nonisolated struct SnippetItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let preview: String
    let colorName: String
    let symbolName: String
}

@MainActor
enum WidgetStore {
    private static var cachedContainer: ModelContainer?

    /// Nil until the app has created the shared store.
    static var container: ModelContainer? {
        if let cachedContainer { return cachedContainer }
        guard SharedStore.storeExists else { return nil }
        let configuration = ModelConfiguration(url: SharedStore.storeURL, cloudKitDatabase: .none)
        cachedContainer = try? ModelContainer(for: Snippet.self, Category.self, configurations: configuration)
        return cachedContainer
    }

    /// A fresh context per read, so each timeline sees the app's latest saves.
    private static func context() -> ModelContext? {
        container.map(ModelContext.init)
    }

    static func allSnippets() -> [Snippet] {
        guard let context = context() else { return [] }
        return (try? context.fetch(FetchDescriptor<Snippet>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
    }

    static func allCategories() -> [Category] {
        guard let context = context() else { return [] }
        return (try? context.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
    }

    /// Pinned first, then most copied, then library order — the same ranking
    /// the app's Shortcuts snippet picker uses.
    static func ranked(_ snippets: [Snippet]) -> [Snippet] {
        snippets.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.copyCount != $1.copyCount { return $0.copyCount > $1.copyCount }
            return $0.sortIndex < $1.sortIndex
        }
    }

    static func snippets(from source: SnippetSource, category: UUID?) -> [Snippet] {
        let snippets = allSnippets()
        switch source {
        case .pinned:
            // Pinned rows keep library order so a tap never moves them; the
            // most-copied snippets fill whatever space is left.
            return snippets.filter(\.isPinned) + mostCopied(snippets.filter { !$0.isPinned })
        case .mostCopied:
            return mostCopied(snippets)
        case .recent:
            // Recently copied first, then the newest additions.
            return snippets.sorted {
                switch ($0.lastCopiedAt, $1.lastCopiedAt) {
                case let (a?, b?): return a > b
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return $0.createdAt > $1.createdAt
                }
            }
        case .category:
            return snippets.filter { $0.category?.uuid == category && category != nil }
        }
    }

    private static func mostCopied(_ snippets: [Snippet]) -> [Snippet] {
        snippets.sorted {
            if $0.copyCount != $1.copyCount { return $0.copyCount > $1.copyCount }
            return $0.sortIndex < $1.sortIndex
        }
    }

    static func snippet(id: UUID) -> Snippet? {
        allSnippets().first { $0.uuid == id }
    }

    static func item(_ snippet: Snippet) -> SnippetItem {
        SnippetItem(
            id: snippet.uuid ?? UUID(),
            title: snippet.displayTitle,
            preview: snippet.preview,
            colorName: snippet.category?.colorName ?? "slate",
            symbolName: snippet.category?.symbolName ?? "doc.on.doc"
        )
    }

    /// Record a copy the way the app does (count + timestamp) and return the
    /// text to put on the clipboard, or nil if the snippet is gone.
    static func recordCopy(of id: UUID) -> String? {
        guard let context = context(),
              let snippet = try? context.fetch(FetchDescriptor<Snippet>()).first(where: { $0.uuid == id })
        else { return nil }
        snippet.copyCount += 1
        snippet.lastCopiedAt = .now
        try? context.save()
        return snippet.content
    }
}
