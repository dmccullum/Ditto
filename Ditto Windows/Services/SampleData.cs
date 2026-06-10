using Ditto.Models;

namespace Ditto.Services;

/// <summary>Seeds starter content on first run (parity with SampleData.swift).</summary>
public static class SampleData
{
    public static void SeedIfNeeded(DittoDbContext db)
    {
        if (db.Categories.Any()) return;

        var hashtags = new Category { Name = "Hashtags", SymbolName = "number", ColorName = "pink", SortIndex = 0 };
        var links = new Category { Name = "Links", SymbolName = "link", ColorName = "blue", SortIndex = 1 };
        var bios = new Category { Name = "Bios & Blurbs", SymbolName = "text.quote", ColorName = "purple", SortIndex = 2 };
        db.Categories.AddRange(hashtags, links, bios);

        var seeds = new (string Title, string Content, Category Category)[]
        {
            ("Daily content tags", "#contentcreator #socialmedia #marketing #digitalmarketing #branding", hashtags),
            ("Launch day", "#newlaunch #comingsoon #excited #staytuned #bigannouncement", hashtags),
            ("Link in bio", "https://linktr.ee/yourbrand", links),
            ("Newsletter signup", "https://yourbrand.com/subscribe", links),
            ("Short bio", "Helping brands tell better stories, one post at a time.", bios),
        };

        var index = 0;
        foreach (var (title, content, category) in seeds)
        {
            db.Snippets.Add(new Snippet { Title = title, Content = content, SortIndex = index++, Category = category });
        }

        db.SaveChanges();
    }
}
