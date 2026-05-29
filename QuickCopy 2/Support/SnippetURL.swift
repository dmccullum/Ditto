//
//  SnippetURL.swift
//  QuickCopy 2 (Ditto)
//
//  Handles incoming `ditto://` links that carry a full snippet inline, so a
//  snippet can be added just by opening a URL — e.g. a shareable link on a
//  company intranet.
//
//  Format:
//      ditto://add?content=<text>&title=<name>&category=<name>&color=<color>&icon=<sf-symbol>
//
//  Only `content` is required. If `category` names a category that doesn't
//  exist yet, it's created (using `color` / `icon` if provided).
//

import Foundation
import SwiftData

enum SnippetURL {
    /// Parse a `ditto://add` URL and insert the snippet it describes.
    /// Returns the created snippet on success, or nil if the URL was invalid.
    @discardableResult
    @MainActor
    static func handle(_ url: URL, context: ModelContext) -> Snippet? {
        guard url.scheme == "ditto", url.host == "add",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return nil }

        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        guard let content = value("content")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else { return nil }

        let title = value("title") ?? ""

        var category: Category?
        if let name = value("category")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            category = resolveCategory(named: name,
                                       color: value("color"),
                                       icon: value("icon"),
                                       context: context)
        }

        let nextIndex = ((try? context.fetch(FetchDescriptor<Snippet>())) ?? [])
            .map(\.sortIndex).max() ?? -1
        let snippet = Snippet(title: title, content: content,
                              sortIndex: nextIndex + 1, category: category)
        context.insert(snippet)
        try? context.save()
        return snippet
    }

    /// Find an existing category by name (case-insensitive), or create one.
    @MainActor
    private static func resolveCategory(named name: String, color: String?, icon: String?,
                                        context: ModelContext) -> Category {
        let existing = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        if let match = existing.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return match
        }
        let nextIndex = existing.map(\.sortIndex).max() ?? -1
        let resolvedColor = SnippetColor(rawValue: color ?? "") != nil ? color! : "blue"
        let category = Category(name: name,
                                symbolName: icon ?? "tag.fill",
                                colorName: resolvedColor,
                                sortIndex: nextIndex + 1)
        context.insert(category)
        return category
    }
}
