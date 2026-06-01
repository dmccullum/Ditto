//
//  ImportExport.swift
//  QuickCopy 2 (Ditto)
//
//  JSON bundle for backing up and sharing your snippet library.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Codable bundle

struct DittoExport: Codable {
    struct ExportCategory: Codable {
        let name: String
        let symbolName: String
        let colorName: String
        let sortIndex: Int
    }
    struct ExportSnippet: Codable {
        let title: String
        let content: String
        let sortIndex: Int
        let isPinned: Bool
        let categoryName: String?
        let createdAt: Date
    }

    let version: Int
    let exportedAt: Date
    let categories: [ExportCategory]
    let snippets: [ExportSnippet]
}

// MARK: - FileDocument

struct DittoDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Helpers

private let isoEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    e.dateEncodingStrategy = .iso8601
    return e
}()

private let isoDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()

func exportDitto(snippets: [Snippet], categories: [Category]) throws -> Data {
    let exportCategories = categories.map {
        DittoExport.ExportCategory(name: $0.name, symbolName: $0.symbolName,
                                   colorName: $0.colorName, sortIndex: $0.sortIndex)
    }
    let exportSnippets = snippets.map {
        DittoExport.ExportSnippet(title: $0.title, content: $0.content,
                                  sortIndex: $0.sortIndex, isPinned: $0.isPinned,
                                  categoryName: $0.category?.name, createdAt: $0.createdAt)
    }
    let bundle = DittoExport(version: 1, exportedAt: .now,
                             categories: exportCategories, snippets: exportSnippets)
    return try isoEncoder.encode(bundle)
}

/// Build a self-contained `ditto://import` link for the given content. The
/// bundle JSON is URL-safe base64-encoded (RFC 4648 §5) so it survives being
/// pasted into a URL — pairs with `SnippetURL.decodeBase64URL`.
func dittoImportLink(snippets: [Snippet], categories: [Category]) -> URL? {
    guard let data = try? exportDitto(snippets: snippets, categories: categories) else { return nil }
    let encoded = data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return URL(string: "ditto://import?data=\(encoded)")
}

func importDitto(data: Data, into context: ModelContext, keepCategories: Bool = true) throws {
    let bundle = try isoDecoder.decode(DittoExport.self, from: data)

    // Merge categories by name (case-insensitive): reuse an existing category
    // rather than creating a duplicate. Existing categories keep their own
    // color/icon so a re-import never clobbers the user's customizations.
    // When keepCategories is false, imported snippets become uncategorized.
    var categoryMap: [String: Category] = [:]
    if keepCategories {
        let existingCategories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        for cat in existingCategories {
            categoryMap[cat.name.lowercased()] = cat
        }
        var maxCategoryIndex = existingCategories.map(\.sortIndex).max() ?? -1
        for ec in bundle.categories where categoryMap[ec.name.lowercased()] == nil {
            maxCategoryIndex += 1
            let category = Category(name: ec.name, symbolName: ec.symbolName,
                                    colorName: ec.colorName, sortIndex: maxCategoryIndex)
            context.insert(category)
            categoryMap[ec.name.lowercased()] = category
        }
    }

    // Skip snippets that already exist (same content + title + category), so
    // re-importing the same bundle is idempotent. New items are appended after
    // the current highest sortIndex.
    let existingSnippets = (try? context.fetch(FetchDescriptor<Snippet>())) ?? []
    func dedupKey(content: String, title: String, categoryName: String?) -> String {
        "\(categoryName?.lowercased() ?? "")\u{1}\(title)\u{1}\(content)"
    }
    var seen = Set(existingSnippets.map {
        dedupKey(content: $0.content, title: $0.title, categoryName: $0.category?.name)
    })
    var maxSnippetIndex = existingSnippets.map(\.sortIndex).max() ?? -1
    for es in bundle.snippets {
        let category = es.categoryName.flatMap { categoryMap[$0.lowercased()] }
        let key = dedupKey(content: es.content, title: es.title, categoryName: category?.name)
        guard !seen.contains(key) else { continue }
        seen.insert(key)
        maxSnippetIndex += 1
        let snippet = Snippet(title: es.title, content: es.content,
                              sortIndex: maxSnippetIndex, isPinned: es.isPinned,
                              category: category)
        snippet.createdAt = es.createdAt   // preserve original date (the init defaults to now)
        context.insert(snippet)
    }

    try context.save()
}
