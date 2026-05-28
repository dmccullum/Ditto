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
    }

    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let first = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first.map(String.init) ?? ""
        return first.isEmpty ? "Untitled snippet" : first
    }

    var preview: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }

    var urlValue: URL? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"),
              !trimmed.contains("\n"),
              let url = URL(string: trimmed) else { return nil }
        return url
    }
}
