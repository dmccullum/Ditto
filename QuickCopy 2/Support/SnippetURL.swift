//
//  SnippetURL.swift
//  QuickCopy 2 (Ditto)
//
//  Handles incoming `ditto://` links so snippets can be added just by opening
//  a URL — e.g. a shareable link on a company intranet.
//
//  Two forms:
//
//  1. A single snippet (human-friendly):
//       ditto://add?content=<text>&title=<name>&category=<name>
//     Only `content` is required. If `category` names one that doesn't exist
//     yet, it's created with default color/icon.
//
//  2. A bundle of snippets and/or whole categories (Claude-friendly):
//       ditto://import?data=<base64url JSON>
//     The JSON is the exact format File → Export produces (DittoExport), so a
//     bundle can carry many snippets plus full categories (name, color, icon).
//

import Foundation
import SwiftData

enum SnippetURL {
    /// Route a `ditto://` URL to the right handler. Returns true if it acted.
    /// `keepCategories` reflects the user's import preference: when false, a
    /// link's category is ignored and snippets land uncategorized.
    @discardableResult
    @MainActor
    static func handle(_ url: URL, context: ModelContext, keepCategories: Bool = true) -> Bool {
        guard url.scheme == "ditto" else { return false }
        switch url.host {
        case "add":    return handleAdd(url, context: context, keepCategories: keepCategories)
        case "import": return handleImport(url, context: context, keepCategories: keepCategories)
        default:       return false
        }
    }

    // MARK: - ditto://add

    @MainActor
    private static func handleAdd(_ url: URL, context: ModelContext, keepCategories: Bool) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return false }

        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        guard let content = value("content")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else { return false }

        let title = value("title") ?? ""

        var category: Category?
        if keepCategories,
           let name = value("category")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            category = resolveCategory(named: name, context: context)
        }

        let nextIndex = ((try? context.fetch(FetchDescriptor<Snippet>())) ?? [])
            .map(\.sortIndex).max() ?? -1
        let snippet = Snippet(title: title, content: content,
                              sortIndex: nextIndex + 1, category: category)
        context.insert(snippet)
        try? context.save()
        return true
    }

    /// Find an existing category by name (case-insensitive), or create a
    /// default one. Color/icon aren't per-snippet concerns, so a category
    /// created via `add` just uses sensible defaults.
    @MainActor
    private static func resolveCategory(named name: String, context: ModelContext) -> Category {
        let existing = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        if let match = existing.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return match
        }
        let nextIndex = existing.map(\.sortIndex).max() ?? -1
        let category = Category(name: name, symbolName: "tag.fill",
                                colorName: "blue", sortIndex: nextIndex + 1)
        context.insert(category)
        return category
    }

    // MARK: - ditto://import

    @MainActor
    private static func handleImport(_ url: URL, context: ModelContext, keepCategories: Bool) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let encoded = components.queryItems?.first(where: { $0.name == "data" })?.value,
              let data = decodeBase64URL(encoded) else { return false }
        do {
            try importDitto(data: data, into: context, keepCategories: keepCategories)
            return true
        } catch {
            return false
        }
    }

    /// Decode URL-safe base64 (RFC 4648 §5): `-`/`_` for `+`/`/`, padding optional.
    private static func decodeBase64URL(_ string: String) -> Data? {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = s.count % 4
        if remainder > 0 {
            s += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: s)
    }
}
