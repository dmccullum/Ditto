using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Ditto.Models;
using Microsoft.EntityFrameworkCore;

namespace Ditto.Services;

// MARK: - Codable bundle (identical shape to ImportExport.swift / DittoExport)

public sealed class DittoExport
{
    [JsonPropertyName("version")] public int Version { get; set; } = 1;
    [JsonPropertyName("exportedAt")] public DateTime ExportedAt { get; set; }
    [JsonPropertyName("categories")] public List<ExportCategory> Categories { get; set; } = new();
    [JsonPropertyName("snippets")] public List<ExportSnippet> Snippets { get; set; } = new();

    public sealed class ExportCategory
    {
        [JsonPropertyName("name")] public string Name { get; set; } = "";
        [JsonPropertyName("symbolName")] public string SymbolName { get; set; } = "tag.fill";
        [JsonPropertyName("colorName")] public string ColorName { get; set; } = "blue";
        [JsonPropertyName("sortIndex")] public int SortIndex { get; set; }
    }

    public sealed class ExportSnippet
    {
        [JsonPropertyName("title")] public string Title { get; set; } = "";
        [JsonPropertyName("content")] public string Content { get; set; } = "";
        [JsonPropertyName("sortIndex")] public int SortIndex { get; set; }
        [JsonPropertyName("isPinned")] public bool IsPinned { get; set; }
        [JsonPropertyName("categoryName")] public string? CategoryName { get; set; }
        [JsonPropertyName("createdAt")] public DateTime CreatedAt { get; set; }
    }
}

/// <summary>
/// JSON backup/share bundle. Matches the Apple apps' format (ISO-8601 dates,
/// the same key names) so a library exported on macOS imports here and back.
/// </summary>
public static class ImportExport
{
    private static readonly JsonSerializerOptions _options = new()
    {
        WriteIndented = true,
        Converters = { new Iso8601DateConverter() },
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
    };

    public static string Export(IEnumerable<Snippet> snippets, IEnumerable<Category> categories)
    {
        var bundle = new DittoExport
        {
            Version = 1,
            ExportedAt = DateTime.Now,
            Categories = categories.Select(c => new DittoExport.ExportCategory
            {
                Name = c.Name, SymbolName = c.SymbolName, ColorName = c.ColorName, SortIndex = c.SortIndex
            }).ToList(),
            Snippets = snippets.Select(s => new DittoExport.ExportSnippet
            {
                Title = s.Title, Content = s.Content, SortIndex = s.SortIndex,
                IsPinned = s.IsPinned, CategoryName = s.Category?.Name, CreatedAt = s.CreatedAt
            }).ToList(),
        };
        return JsonSerializer.Serialize(bundle, _options);
    }

    /// <summary>Build a self-contained ditto://import link (URL-safe base64).</summary>
    public static string? ImportLink(IEnumerable<Snippet> snippets, IEnumerable<Category> categories)
    {
        try
        {
            var json = Export(snippets, categories);
            var b64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(json))
                .Replace('+', '-').Replace('/', '_').TrimEnd('=');
            return $"ditto://import?data={b64}";
        }
        catch { return null; }
    }

    /// <summary>
    /// Merge an exported bundle into the store. Categories merge by name
    /// (case-insensitive); snippets de-dupe on (category, title, content) so a
    /// re-import is idempotent. When keepCategories is false, snippets land
    /// uncategorized. Mirrors importDitto() in the Swift app.
    /// </summary>
    public static void Import(DittoDbContext db, string json, bool keepCategories = true)
    {
        var bundle = JsonSerializer.Deserialize<DittoExport>(json, _options)
                     ?? throw new InvalidDataException("Not a Ditto library file.");

        var categoryMap = new Dictionary<string, Category>(StringComparer.OrdinalIgnoreCase);
        if (keepCategories)
        {
            var existing = db.Categories.ToList();
            foreach (var c in existing) categoryMap[c.Name] = c;
            var maxIndex = existing.Count > 0 ? existing.Max(c => c.SortIndex) : -1;
            foreach (var ec in bundle.Categories)
            {
                if (categoryMap.ContainsKey(ec.Name)) continue;
                maxIndex++;
                var cat = new Category
                {
                    Name = ec.Name, SymbolName = ec.SymbolName,
                    ColorName = ec.ColorName, SortIndex = maxIndex
                };
                db.Categories.Add(cat);
                categoryMap[ec.Name] = cat;
            }
        }

        var existingSnippets = db.Snippets.Include(s => s.Category).ToList();
        string Key(string content, string title, string? categoryName)
            => $"{(categoryName ?? "").ToLowerInvariant()}{title}{content}";

        var seen = new HashSet<string>(
            existingSnippets.Select(s => Key(s.Content, s.Title, s.Category?.Name)));
        var maxSnippetIndex = existingSnippets.Count > 0 ? existingSnippets.Max(s => s.SortIndex) : -1;

        foreach (var es in bundle.Snippets)
        {
            Category? category = null;
            if (es.CategoryName != null) categoryMap.TryGetValue(es.CategoryName, out category);
            var key = Key(es.Content, es.Title, category?.Name);
            if (!seen.Add(key)) continue;
            maxSnippetIndex++;
            db.Snippets.Add(new Snippet
            {
                Title = es.Title, Content = es.Content, SortIndex = maxSnippetIndex,
                IsPinned = es.IsPinned, Category = category, CreatedAt = es.CreatedAt
            });
        }

        db.SaveChanges();
    }
}

/// <summary>Serializes dates as ISO-8601 UTC ("...Z"), matching Swift's .iso8601.</summary>
internal sealed class Iso8601DateConverter : JsonConverter<DateTime>
{
    public override DateTime Read(ref Utf8JsonReader reader, Type t, JsonSerializerOptions o)
    {
        var s = reader.GetString();
        return DateTime.TryParse(s, CultureInfo.InvariantCulture,
            DateTimeStyles.AdjustToUniversal | DateTimeStyles.RoundtripKind, out var d)
            ? d.ToLocalTime()
            : DateTime.Now;
    }

    public override void Write(Utf8JsonWriter writer, DateTime value, JsonSerializerOptions o)
        => writer.WriteStringValue(value.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture));
}
