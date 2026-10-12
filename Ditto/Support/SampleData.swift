//
//  SampleData.swift
//  Ditto
//
//  Seeds a few example categories + snippets the first time the app runs, so
//  it doesn't open to an empty void.
//

import SwiftData
import Foundation

enum SampleData {
    /// Inserts starter content only if the store is completely empty.
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Category>())) ?? 0
        guard existing == 0 else { return }

        let hashtags = Category(name: "Hashtags", symbolName: "number", colorName: "pink", sortIndex: 0)
        let links = Category(name: "Links", symbolName: "link", colorName: "blue", sortIndex: 1)
        let bios = Category(name: "Bios & Blurbs", symbolName: "text.quote", colorName: "purple", sortIndex: 2)

        context.insert(hashtags)
        context.insert(links)
        context.insert(bios)

        let seeds: [(String, String, Category)] = [
            ("Daily content tags", "#contentcreator #socialmedia #marketing #digitalmarketing #branding", hashtags),
            ("Launch day", "#newlaunch #comingsoon #excited #staytuned #bigannouncement", hashtags),
            ("Link in bio", "https://linktr.ee/yourbrand", links),
            ("Newsletter signup", "https://yourbrand.com/subscribe", links),
            ("Short bio", "Helping brands tell better stories, one post at a time. ✨", bios)
        ]

        for (index, seed) in seeds.enumerated() {
            let snippet = Snippet(title: seed.0, content: seed.1, sortIndex: index, category: seed.2)
            context.insert(snippet)
        }

        try? context.save()
    }
}
