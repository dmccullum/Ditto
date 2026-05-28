import SwiftData
import Foundation

enum SampleData {
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Category>())) ?? 0
        guard existing == 0 else { return }

        let hashtags = Category(name: "Hashtags", symbolName: "number", colorName: "pink", sortIndex: 0)
        let links    = Category(name: "Links",    symbolName: "link",   colorName: "blue", sortIndex: 1)
        let bios     = Category(name: "Bios & Blurbs", symbolName: "text.quote", colorName: "purple", sortIndex: 2)

        context.insert(hashtags)
        context.insert(links)
        context.insert(bios)

        let seeds: [(String, String, Category)] = [
            ("Daily content tags", "#contentcreator #socialmedia #marketing #digitalmarketing #branding", hashtags),
            ("Launch day", "#newlaunch #comingsoon #excited #staytuned #bigannouncement", hashtags),
            ("Link in bio", "https://linktr.ee/yourbrand", links),
            ("Newsletter signup", "https://yourbrand.com/subscribe", links),
            ("Short bio", "Helping brands tell better stories, one post at a time. ✨", bios),
        ]
        for (i, seed) in seeds.enumerated() {
            context.insert(Snippet(title: seed.0, content: seed.1, sortIndex: i, category: seed.2))
        }
        try? context.save()
    }
}
