//
//  DemoLibrary.swift
//  Ditto
//
//  A throwaway, in-memory library for screenshots and demos. Launch a Debug
//  build with `-DittoDemo` and Ditto runs against this instead of the real
//  store: nothing is read from or written to disk, and it vanishes on quit.
//  Compiled out of Release builds entirely.
//

#if DEBUG
import SwiftData
import Foundation

enum DemoLibrary {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-DittoDemo")
    }

    /// An in-memory, local-only container filled with the demo library.
    @MainActor
    static func makeContainer(schema: Schema) -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try! ModelContainer(for: schema, configurations: config)
        seed(container.mainContext)
        return container
    }

    private struct Seed {
        let title: String
        let content: String
        var copies = 0
        var pinned = false
    }

    private static let library: [(name: String, symbol: String, color: String, snippets: [Seed])] = [
        ("Hashtags", "number", "pink", [
            Seed(title: "Daily content", content: "#contentcreator #socialmedia #marketing #digitalmarketing #branding", copies: 42, pinned: true),
            Seed(title: "Launch week", content: "#newlaunch #comingsoon #behindthescenes #smallbusiness #launchday", copies: 12),
            Seed(title: "Travel", content: "#wanderlust #slowtravel #passportready #weekendaway #travelgram", copies: 7),
            Seed(title: "Coffee shop", content: "#coffeetime #latteart #coffeelover #morningritual #thirdwave", copies: 3)
        ]),
        ("Links", "link", "blue", [
            Seed(title: "Link in bio", content: "https://fernwood.studio/links", copies: 38, pinned: true),
            Seed(title: "Booking calendar", content: "https://fernwood.studio/book", copies: 21),
            Seed(title: "Newsletter", content: "https://fernwood.studio/newsletter", copies: 15),
            Seed(title: "Portfolio", content: "https://fernwood.studio/work", copies: 6)
        ]),
        ("Email Replies", "envelope.fill", "teal", [
            Seed(title: "Thanks for reaching out", content: """
                Hi there,

                Thanks so much for reaching out! I'd love to hear more about your project. Could you share a little about your timeline and budget? I'll get back to you within one business day.

                Best,
                Sam
                """, copies: 27, pinned: true),
            Seed(title: "Invoice sent", content: "Hi! Your invoice is attached. Payment is due within 14 days — let me know if you have any questions. Thanks again for a great project!", copies: 11),
            Seed(title: "Not a fit right now", content: "Thank you for thinking of me! My calendar is full through next month, but I'd be glad to recommend a few designers I trust.", copies: 4),
            Seed(title: "Out of office", content: "I'm away until Monday with limited access to email. For anything urgent, reply with URGENT in the subject line.", copies: 2)
        ]),
        ("Captions", "sparkles", "orange", [
            Seed(title: "Giveaway", content: "🎉 GIVEAWAY TIME! To enter: 1) Follow us 2) Like this post 3) Tag two friends who'd love this. Winner announced Friday!", copies: 9),
            Seed(title: "New on the blog", content: "New on the blog → we're breaking down our whole rebrand, from first sketch to final files. Link in bio. 📖", copies: 8),
            Seed(title: "Behind the scenes", content: "A little peek behind the curtain ☕️ Monday mornings look like this.", copies: 5)
        ]),
        ("Bios & Blurbs", "text.quote", "purple", [
            Seed(title: "Short bio", content: "Designer & storyteller helping small brands look as good as they are. ✨ Based in Portland.", copies: 10),
            Seed(title: "One-liner", content: "Making small brands impossible to scroll past.", copies: 6),
            Seed(title: "Speaker intro", content: "Sam Rivera is the founder of Fernwood Studio, a two-person design practice that has helped more than 120 independent businesses find their visual voice.", copies: 2)
        ]),
        ("Dev", "terminal.fill", "indigo", [
            Seed(title: "Undo last commit", content: "git reset --soft HEAD~1", copies: 14),
            Seed(title: "Flush DNS", content: "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder", copies: 3),
            Seed(title: "Brand palette", content: "#2F5D50  #F2C14E  #F7F3EC  #1E1E1E", copies: 7)
        ])
    ]

    private static func seed(_ context: ModelContext) {
        var snippetIndex = 0
        for (categoryIndex, entry) in library.enumerated() {
            let category = Category(name: entry.name, symbolName: entry.symbol, colorName: entry.color, sortIndex: categoryIndex)
            context.insert(category)
            for seed in entry.snippets {
                let snippet = Snippet(title: seed.title, content: seed.content, sortIndex: snippetIndex, isPinned: seed.pinned, category: category)
                // Stagger dates so "recent" and "most copied" views look lived-in.
                snippet.createdAt = .now.addingTimeInterval(Double(-86_400 * (30 - snippetIndex)))
                snippet.copyCount = seed.copies
                if seed.copies > 0 {
                    snippet.lastCopiedAt = .now.addingTimeInterval(Double(-3_600 * (snippetIndex + 1)))
                }
                context.insert(snippet)
                snippetIndex += 1
            }
        }
        try? context.save()
    }
}
#endif
