using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Windows.Media;

namespace Ditto.Models;

/// <summary>
/// A single copyable snippet. Mirrors the Swift @Model of the same name so the
/// JSON export format stays identical across macOS, iOS and Windows.
/// </summary>
public class Snippet : ObservableObject
{
    [Key] public int Id { get; set; }

    private string _title = "";
    public string Title { get => _title; set { if (Set(ref _title, value)) { OnPropertyChanged(nameof(DisplayTitle)); } } }

    private string _content = "";
    public string Content
    {
        get => _content;
        set
        {
            if (Set(ref _content, value))
            {
                OnPropertyChanged(nameof(DisplayTitle));
                OnPropertyChanged(nameof(Preview));
                OnPropertyChanged(nameof(CharCountLabel));
                OnPropertyChanged(nameof(UrlValue));
            }
        }
    }

    public int SortIndex { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.Now;

    private DateTime? _lastCopiedAt;
    public DateTime? LastCopiedAt { get => _lastCopiedAt; set => Set(ref _lastCopiedAt, value); }

    private int _copyCount;
    public int CopyCount { get => _copyCount; set => Set(ref _copyCount, value); }

    private bool _isPinned;
    public bool IsPinned { get => _isPinned; set => Set(ref _isPinned, value); }

    // Relationship: a snippet optionally belongs to one category.
    public int? CategoryId { get; set; }

    private Category? _category;
    public Category? Category
    {
        get => _category;
        set
        {
            if (Set(ref _category, value))
            {
                CategoryId = value?.Id;
                OnPropertyChanged(nameof(Glyph));
                OnPropertyChanged(nameof(ColorName));
                OnPropertyChanged(nameof(AccentBrush));
                OnPropertyChanged(nameof(CardBackgroundBrush));
                OnPropertyChanged(nameof(CardBorderBrush));
            }
        }
    }

    // MARK: - Derived display helpers (parity with Snippet.swift)

    [NotMapped] public string ColorName => Category?.ColorName ?? "blue";
    [NotMapped] public string Glyph => SymbolMap.Glyph(Category?.SymbolName ?? "doc.text");
    [NotMapped] public Brush AccentBrush => ColorMap.Brush(ColorName);
    [NotMapped] public Brush CardBackgroundBrush => ColorMap.CardBackground(ColorName);
    [NotMapped] public Brush CardBorderBrush => ColorMap.CardBorder(ColorName);
    [NotMapped] public string PinGlyph => SymbolMap.Glyph("pin.fill");

    [NotMapped]
    public string DisplayTitle
    {
        get
        {
            var t = Title.Trim();
            if (t.Length > 0) return t;
            var firstLine = Content.Trim().Split('\n', 2, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? "";
            return firstLine.Length == 0 ? "Untitled snippet" : firstLine;
        }
    }

    [NotMapped] public string Preview => Content.Trim().Replace("\n", " ");
    [NotMapped] public string CharCountLabel => $"{Content.Length} chars";

    [NotMapped]
    public Uri? UrlValue
    {
        get
        {
            var t = Content.Trim();
            if ((!t.StartsWith("http://") && !t.StartsWith("https://")) || t.Contains('\n')) return null;
            return Uri.TryCreate(t, UriKind.Absolute, out var u) ? u : null;
        }
    }
}
