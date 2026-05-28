//
//  Category.swift
//  QuickCopy 2
//
//  A named, colorful group that holds snippets (e.g. "Hashtags", "Links").
//

import SwiftData
import Foundation

@Model
final class Category {
    var name: String
    var symbolName: String   // SF Symbol, e.g. "number", "link"
    var colorName: String    // key into SnippetColor palette
    var sortIndex: Int
    var createdAt: Date

    // Deleting a category deletes its snippets.
    @Relationship(deleteRule: .cascade, inverse: \Snippet.category)
    var snippets: [Snippet] = []

    init(
        name: String,
        symbolName: String = "tag",
        colorName: String = "blue",
        sortIndex: Int = 0
    ) {
        self.name = name
        self.symbolName = symbolName
        self.colorName = colorName
        self.sortIndex = sortIndex
        self.createdAt = .now
    }
}
