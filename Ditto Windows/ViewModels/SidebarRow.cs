using System.Windows.Media;
using Ditto.Models;

namespace Ditto.ViewModels;

/// <summary>
/// A single row in the sidebar ListBox. "Library" rows (All / Frequent) and
/// per-category rows share this type; the grouped ListBox renders section
/// headers from <see cref="Section"/>.
/// </summary>
public sealed class SidebarRow : ObservableObject
{
    public string Section { get; init; } = "Library";
    public string Glyph { get; init; } = "";
    public Brush GlyphBrush { get; init; } = Brushes.Gray;
    public string Title { get; init; } = "";
    public SidebarSelection Selection { get; init; } = SidebarSelection.All;
    public Category? Category { get; init; }
    public bool ShowCount { get; init; } = true;

    private string _countText = "";
    public string CountText { get => _countText; set => Set(ref _countText, value); }
}
