using System.Text;
using Ditto.Models;
using Microsoft.EntityFrameworkCore;

namespace Ditto.Services;

/// <summary>
/// Handles incoming ditto:// links (parity with SnippetURL.swift):
///   ditto://add?content=..&title=..&category=..
///   ditto://import?data=&lt;base64url JSON&gt;
/// </summary>
public static class DittoUrl
{
    public static bool Handle(string url, DittoDbContext db, bool keepCategories = true)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme != "ditto") return false;
        return uri.Host switch
        {
            "add"    => HandleAdd(uri, db, keepCategories),
            "import" => HandleImport(uri, db, keepCategories),
            _        => false
        };
    }

    private static Dictionary<string, string> Query(Uri uri)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var q = uri.Query.TrimStart('?');
        if (q.Length == 0) return result;
        foreach (var pair in q.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var i = pair.IndexOf('=');
            if (i < 0) { result[Uri.UnescapeDataString(pair)] = ""; continue; }
            var k = Uri.UnescapeDataString(pair[..i]);
            var v = Uri.UnescapeDataString(pair[(i + 1)..]);
            result[k] = v;
        }
        return result;
    }

    private static bool HandleAdd(Uri uri, DittoDbContext db, bool keepCategories)
    {
        var q = Query(uri);
        if (!q.TryGetValue("content", out var content)) return false;
        content = content.Trim();
        if (content.Length == 0) return false;

        var title = q.TryGetValue("title", out var t) ? t : "";

        Category? category = null;
        if (keepCategories && q.TryGetValue("category", out var name) && name.Trim().Length > 0)
            category = ResolveCategory(name.Trim(), db);

        var nextIndex = (db.Snippets.Any() ? db.Snippets.Max(s => s.SortIndex) : -1) + 1;
        db.Snippets.Add(new Snippet
        {
            Title = title, Content = content, SortIndex = nextIndex, Category = category
        });
        db.SaveChanges();
        return true;
    }

    private static Category ResolveCategory(string name, DittoDbContext db)
    {
        var existing = db.Categories.ToList();
        var match = existing.FirstOrDefault(c => string.Equals(c.Name, name, StringComparison.OrdinalIgnoreCase));
        if (match != null) return match;

        var nextIndex = (existing.Count > 0 ? existing.Max(c => c.SortIndex) : -1) + 1;
        var cat = new Category { Name = name, SymbolName = "tag.fill", ColorName = "blue", SortIndex = nextIndex };
        db.Categories.Add(cat);
        return cat;
    }

    private static bool HandleImport(Uri uri, DittoDbContext db, bool keepCategories)
    {
        var q = Query(uri);
        if (!q.TryGetValue("data", out var encoded)) return false;
        var bytes = DecodeBase64Url(encoded);
        if (bytes == null) return false;
        try
        {
            ImportExport.Import(db, Encoding.UTF8.GetString(bytes), keepCategories);
            return true;
        }
        catch { return false; }
    }

    /// <summary>Decode URL-safe base64 (RFC 4648 §5): -/_ for +//, padding optional.</summary>
    private static byte[]? DecodeBase64Url(string s)
    {
        s = s.Replace('-', '+').Replace('_', '/');
        switch (s.Length % 4)
        {
            case 2: s += "=="; break;
            case 3: s += "="; break;
        }
        try { return Convert.FromBase64String(s); }
        catch { return null; }
    }
}
