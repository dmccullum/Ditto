//
//  SnippetSearch.swift
//  Ditto
//
//  Global snippet search with deliberately title-first ranking.
//

import Foundation

enum SnippetSearch {
    static func results(for query: String, in snippets: [Snippet]) -> [Snippet] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return snippets
            .compactMap { snippet -> (snippet: Snippet, rank: Int)? in
                guard !query.isEmpty else { return (snippet, 6) }

                let title = snippet.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if title.localizedCaseInsensitiveCompare(query) == .orderedSame {
                    return (snippet, 0)
                }
                if title.range(of: query, options: [.anchored, .caseInsensitive],
                               locale: .current) != nil {
                    return (snippet, 1)
                }
                if title.localizedStandardContains(query) {
                    return (snippet, 2)
                }
                if snippet.content.range(of: query, options: [.anchored, .caseInsensitive],
                                         locale: .current) != nil {
                    return (snippet, 3)
                }
                if snippet.content.localizedStandardContains(query) {
                    return (snippet, 4)
                }
                return nil
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                if lhs.snippet.isPinned != rhs.snippet.isPinned { return lhs.snippet.isPinned }
                if lhs.snippet.copyCount != rhs.snippet.copyCount {
                    return lhs.snippet.copyCount > rhs.snippet.copyCount
                }
                if lhs.snippet.sortIndex != rhs.snippet.sortIndex {
                    return lhs.snippet.sortIndex < rhs.snippet.sortIndex
                }
                return lhs.snippet.displayTitle.localizedStandardCompare(rhs.snippet.displayTitle) == .orderedAscending
            }
            .map(\.snippet)
    }
}
