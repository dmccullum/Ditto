//
//  Snippet.swift
//  Ditto
//

import SwiftData
import Foundation

@Model
final class Snippet {
    var title: String = ""
    var content: String = ""
    var sortIndex: Int = 0
    var createdAt: Date = Date.now
    var lastCopiedAt: Date? = nil
    var copyCount: Int = 0
    var isPinned: Bool = false
    var category: Category? = nil
    /// Stable identity for App Intents / Spotlight. Optional (schema default
    /// nil) so existing rows migrate cleanly; backfilled at launch by DittoStore.
    var uuid: UUID? = nil

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
        self.isPinned = isPinned
        self.category = category
        self.uuid = UUID()
    }

    var urlValue: URL? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"),
              !trimmed.contains("\n"),
              let url = URL(string: trimmed) else { return nil }
        return url
    }

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

    var preview: String {
        content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// A sortIndex below every existing snippet, so a newly created snippet
    /// lands at a deterministic spot (the top) instead of tying with index 0.
    static func topSortIndex(in context: ModelContext) -> Int {
        var descriptor = FetchDescriptor<Snippet>(sortBy: [SortDescriptor(\Snippet.sortIndex)])
        descriptor.fetchLimit = 1
        let lowest = (try? context.fetch(descriptor))?.first?.sortIndex ?? 1
        return lowest - 1
    }
}
