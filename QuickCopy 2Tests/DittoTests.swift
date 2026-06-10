//
//  DittoTests.swift
//  DittoTests
//
//  Unit tests for the pure logic that backs sharing and import/export:
//  the JSON bundle, ditto:// URL handling, and sort-index bookkeeping.
//

import Testing
import Foundation
import SwiftData
@testable import Ditto

/// The model type, not Foundation's Objective-C `Category`.
private typealias Category = Ditto.Category

@MainActor
@Suite struct DittoTests {

    /// Runs a test body against a fresh in-memory store. The container is
    /// kept alive for the whole body — models crash if it deallocates early.
    private func withStore(_ body: (ModelContext) throws -> Void) throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Snippet.self, Category.self,
                                           configurations: config)
        try withExtendedLifetime(container) {
            try body(container.mainContext)
        }
    }

    @discardableResult
    private func seed(_ context: ModelContext) throws -> (Category, [Snippet]) {
        let category = Category(name: "Hashtags", symbolName: "number",
                                colorName: "pink", sortIndex: 0)
        context.insert(category)
        let snippets = [
            Snippet(title: "Daily", content: "#one #two", sortIndex: 0,
                    isPinned: true, category: category),
            Snippet(title: "", content: "Line one\nLine two", sortIndex: 1),
            Snippet(title: "Emoji", content: "✨🚀 ünïcødé + / =", sortIndex: 2),
        ]
        snippets.forEach(context.insert)
        try context.save()
        return (category, snippets)
    }

    // MARK: - Export / import bundle

    @Test func exportImportRoundTrip() throws {
        try withStore { source in
            let (category, snippets) = try seed(source)
            let data = try exportDitto(snippets: snippets, categories: [category])

            try withStore { destination in
                try importDitto(data: data, into: destination)

                let categories = try destination.fetch(FetchDescriptor<Category>())
                let imported = try destination.fetch(FetchDescriptor<Snippet>())
                #expect(categories.count == 1)
                #expect(categories.first?.name == "Hashtags")
                #expect(imported.count == 3)

                let daily = try #require(imported.first { $0.title == "Daily" })
                #expect(daily.category?.name == "Hashtags")
                #expect(daily.isPinned)
                #expect(daily.content == "#one #two")
            }
        }
    }

    @Test func importIsIdempotent() throws {
        try withStore { source in
            let (category, snippets) = try seed(source)
            let data = try exportDitto(snippets: snippets, categories: [category])

            try withStore { destination in
                try importDitto(data: data, into: destination)
                try importDitto(data: data, into: destination)

                let snippetCount = try destination.fetch(FetchDescriptor<Snippet>()).count
                let categoryCount = try destination.fetch(FetchDescriptor<Category>()).count
                #expect(snippetCount == 3)
                #expect(categoryCount == 1)
            }
        }
    }

    @Test func importCanDropCategories() throws {
        try withStore { source in
            let (category, snippets) = try seed(source)
            let data = try exportDitto(snippets: snippets, categories: [category])

            try withStore { destination in
                try importDitto(data: data, into: destination, keepCategories: false)

                let categories = try destination.fetch(FetchDescriptor<Category>())
                #expect(categories.isEmpty)
                let imported = try destination.fetch(FetchDescriptor<Snippet>())
                #expect(imported.count == 3)
                #expect(imported.allSatisfy { $0.category == nil })
            }
        }
    }

    @Test func importMergesCategoriesCaseInsensitively() throws {
        try withStore { source in
            let (category, snippets) = try seed(source)
            let data = try exportDitto(snippets: snippets, categories: [category])

            try withStore { destination in
                let existing = Category(name: "HASHTAGS", symbolName: "flame",
                                        colorName: "red", sortIndex: 0)
                destination.insert(existing)
                try destination.save()

                try importDitto(data: data, into: destination)

                let categories = try destination.fetch(FetchDescriptor<Category>())
                #expect(categories.count == 1)
                // The existing category keeps its own look — imports never clobber it.
                #expect(categories.first?.symbolName == "flame")
            }
        }
    }

    // MARK: - ditto:// links

    @Test func importLinkRoundTrip() throws {
        try withStore { source in
            let (category, snippets) = try seed(source)
            let link = try #require(dittoImportLink(snippets: snippets, categories: [category]))

            // URL-safe base64: no characters that need escaping in a query value
            // (the payload after "data=").
            let query = try #require(link.query)
            let payload = try #require(query.split(separator: "=", maxSplits: 1).last.map(String.init))
            #expect(!payload.contains("+") && !payload.contains("/") && !payload.contains("="))

            try withStore { destination in
                #expect(SnippetURL.handle(link, context: destination))
                let snippetCount = try destination.fetch(FetchDescriptor<Snippet>()).count
                let categoryCount = try destination.fetch(FetchDescriptor<Category>()).count
                #expect(snippetCount == 3)
                #expect(categoryCount == 1)
            }
        }
    }

    @Test func addLinkCreatesSnippetAndCategory() throws {
        try withStore { context in
            let url = try #require(URL(string:
                "ditto://add?content=Hello%20world&title=Greeting&category=Intros"))

            #expect(SnippetURL.handle(url, context: context))

            let fetched = try context.fetch(FetchDescriptor<Snippet>())
            let snippet = try #require(fetched.first)
            #expect(snippet.title == "Greeting")
            #expect(snippet.content == "Hello world")
            #expect(snippet.category?.name == "Intros")
        }
    }

    @Test func addLinkReusesCategoryCaseInsensitively() throws {
        try withStore { context in
            let existing = Category(name: "intros", symbolName: "person",
                                    colorName: "teal", sortIndex: 0)
            context.insert(existing)
            try context.save()

            let url = try #require(URL(string: "ditto://add?content=Hi&category=INTROS"))
            #expect(SnippetURL.handle(url, context: context))

            let categoryCount = try context.fetch(FetchDescriptor<Category>()).count
            #expect(categoryCount == 1)
            let fetched = try context.fetch(FetchDescriptor<Snippet>())
            let snippet = try #require(fetched.first)
            #expect(snippet.category?.persistentModelID == existing.persistentModelID)
        }
    }

    @Test func addLinkIgnoresCategoryWhenAskedTo() throws {
        try withStore { context in
            let url = try #require(URL(string: "ditto://add?content=Hi&category=Intros"))
            #expect(SnippetURL.handle(url, context: context, keepCategories: false))

            let categories = try context.fetch(FetchDescriptor<Category>())
            #expect(categories.isEmpty)
            let fetched = try context.fetch(FetchDescriptor<Snippet>())
            let snippet = try #require(fetched.first)
            #expect(snippet.category == nil)
        }
    }

    @Test func addLinkRequiresContent() throws {
        try withStore { context in
            let url = try #require(URL(string: "ditto://add?title=NoContent"))
            #expect(!SnippetURL.handle(url, context: context))
            let snippets = try context.fetch(FetchDescriptor<Snippet>())
            #expect(snippets.isEmpty)
        }
    }

    // MARK: - Sort index

    @Test func topSortIndexPlacesNewSnippetsFirst() throws {
        try withStore { context in
            #expect(Snippet.topSortIndex(in: context) == 0)

            try seed(context)
            let top = Snippet.topSortIndex(in: context)
            #expect(top == -1)

            context.insert(Snippet(title: "New", content: "x", sortIndex: top))
            try context.save()
            let lowest = try context.fetch(FetchDescriptor<Snippet>())
                .min { $0.sortIndex < $1.sortIndex }
            #expect(lowest?.title == "New")
        }
    }

    // MARK: - Model helpers

    @Test func displayTitleFallsBackToFirstContentLine() {
        #expect(Snippet(title: "  ", content: "First line\nSecond").displayTitle == "First line")
        #expect(Snippet(title: "Named", content: "Body").displayTitle == "Named")
        #expect(Snippet(title: "", content: "   ").displayTitle == "Untitled snippet")
    }

    @Test func newModelsGetStableUUIDs() {
        let a = Snippet(content: "one")
        let b = Snippet(content: "two")
        #expect(a.uuid != nil)
        #expect(a.uuid != b.uuid)
        #expect(Category(name: "C").uuid != nil)
    }
}
