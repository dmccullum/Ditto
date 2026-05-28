import SwiftData
import Foundation

@Model
final class Category {
    var name: String = ""
    var symbolName: String = "tag.fill"
    var colorName: String = "blue"
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Snippet.category)
    var snippets: [Snippet] = []

    init(
        name: String,
        symbolName: String = "tag.fill",
        colorName: String = "blue",
        sortIndex: Int = 0
    ) {
        self.name = name
        self.symbolName = symbolName
        self.colorName = colorName
        self.sortIndex = sortIndex
    }
}
