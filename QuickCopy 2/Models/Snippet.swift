//
//  Snippet.swift
//  QuickCopy 2
//
//  A single piece of reusable text that gets copied to the clipboard.
//

import SwiftData
import Foundation

@Model
final class Snippet {
    var title: String          // optional human name; blank = derive from content
    var content: String        // the text that gets copied
    var sortIndex: Int
    var createdAt: Date
    var lastCopiedAt: Date?
    var copyCount: Int
    var isPinned: Bool
    var category: Category?

    init(
        title: String = "",
        content: String,
        sortIndex: Int = 0,
        isPinned: Bool = false,
        category: Category? = nil
    ) {
        self.title = title
        self.content = content
        self.sortIndex = sortIndex
        self.createdAt = .now
        self.copyCount = 0
        self.isPinned = isPinned
        self.category = category
    }

    /// Non-nil when content is a single valid http/https URL.
    var urlValue: URL? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"),
              !trimmed.contains("\n"),
              let url = URL(string: trimmed) else { return nil }
        return url
    }

    /// What to show as the row's heading: the user's title, or the first
    /// meaningful line of the content if they never named it.
    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { return trimmedTitle }

        let firstLine = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        return firstLine.isEmpty ? "Untitled snippet" : firstLine
    }

    /// A one-line preview of the content for secondary text.
    var preview: String {
        content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }
}
