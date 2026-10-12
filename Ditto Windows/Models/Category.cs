using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Windows.Media;

namespace Ditto.Models;

/// <summary>
/// A named, colored, icon-tagged group of snippets. Mirrors Category.swift.
/// SymbolName stores the original SF Symbol identifier (e.g. "tag.fill") so
/// exports round-trip with the Apple apps; it is mapped to a Segoe glyph only
/// at display time via <see cref="SymbolMap"/>.
/// </summary>
public class Category : ObservableObject
{
    [Key] public int Id { get; set; }

    private string _name = "";
    public string Name { get => _name; set => Set(ref _name, value); }

    private string _symbolName = "tag.fill";
    public string SymbolName
    {
        get => _symbolName;
        set { if (Set(ref _symbolName, value)) OnPropertyChanged(nameof(Glyph)); }
    }

    private string _colorName = "blue";
    public string ColorName
    {
        get => _colorName;
        set { if (Set(ref _colorName, value)) OnPropertyChanged(nameof(Brush)); }
    }

    public int SortIndex { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.Now;

    // Cascade delete is configured in DittoDbContext so removing a category
    // removes its snippets (matching the Swift .cascade rule).
    public List<Snippet> Snippets { get; set; } = new();

    [NotMapped] public string Glyph => SymbolMap.Glyph(SymbolName);
    [NotMapped] public Brush Brush => ColorMap.Brush(ColorName);

    /// <summary>Raises change notifications for the live snippet count badge.</summary>
    public void NotifyCountChanged() => OnPropertyChanged(nameof(SnippetCount));
    [NotMapped] public int SnippetCount => Snippets.Count;
}
