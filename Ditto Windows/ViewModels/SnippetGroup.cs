using System.Collections.ObjectModel;
using System.Windows.Media;
using Ditto.Models;

namespace Ditto.ViewModels;

/// <summary>
/// One collapsible section in the detail pane. In ungrouped views a single
/// group with ShowHeader=false carries every card.
/// </summary>
public sealed class SnippetGroup : ObservableObject
{
    public string Id { get; }
    public string Title { get; }
    public string Glyph { get; }
    public Brush Accent { get; }
    public bool ShowHeader { get; }
    public ObservableCollection<Snippet> Snippets { get; }

    private bool _isCollapsed;
    public bool IsCollapsed { get => _isCollapsed; set => Set(ref _isCollapsed, value); }

    public int Count => Snippets.Count;

    public SnippetGroup(string id, string title, string glyph, Brush accent,
                        IEnumerable<Snippet> snippets, bool showHeader, bool collapsed)
    {
        Id = id;
        Title = title;
        Glyph = glyph;
        Accent = accent;
        ShowHeader = showHeader;
        Snippets = new ObservableCollection<Snippet>(snippets);
        _isCollapsed = collapsed;
    }
}
