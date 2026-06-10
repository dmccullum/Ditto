using System.Collections.ObjectModel;
using System.Windows.Media;
using Ditto.Models;
using Ditto.Services;
using Microsoft.EntityFrameworkCore;

namespace Ditto.ViewModels;

/// <summary>
/// Drives the main window: sidebar selection, search, grouping, zoom, and all
/// snippet/category mutations. A single long-lived DbContext backs the app
/// (fine for a single-user desktop store).
/// </summary>
public sealed class MainViewModel : ObservableObject
{
    private readonly DittoDbContext _db;
    public SettingsService Settings { get; }

    // Card size: 0 = smallest … 4 = largest (parity with sizeLevel in Swift).
    private static readonly double[] CardWidths = { 150, 185, 225, 275, 330 };
    public const int MinSizeLevel = 0;
    public const int MaxSizeLevel = 4;

    // Persisted collapse state for detail groups, keyed by group id.
    private readonly HashSet<string> _collapsedGroups = new();

    public ObservableCollection<Category> Categories { get; } = new();
    public ObservableCollection<SnippetGroup> Groups { get; } = new();
    public ObservableCollection<SidebarRow> SidebarRows { get; } = new();

    public MainViewModel(DittoDbContext db, SettingsService settings)
    {
        _db = db;
        Settings = settings;
        _selection = SidebarSelection.All;
        Reload();
    }

    public DittoDbContext Db => _db;

    // MARK: - Observable state

    private SidebarSelection _selection;
    public SidebarSelection Selection
    {
        get => _selection;
        set
        {
            if (Set(ref _selection, value))
            {
                OnPropertyChanged(nameof(DetailTitle));
                OnPropertyChanged(nameof(IsAllView));
                OnPropertyChanged(nameof(IsReorderable));
                SyncSelectedRow();
                Rebuild();
            }
        }
    }

    private SidebarRow? _selectedRow;
    /// <summary>Two-way bound to the sidebar ListBox's SelectedItem.</summary>
    public SidebarRow? SelectedRow
    {
        get => _selectedRow;
        set
        {
            if (Set(ref _selectedRow, value) && value != null)
                Selection = value.Selection;
        }
    }

    private void SyncSelectedRow()
    {
        var match = SidebarRows.FirstOrDefault(r => r.Selection.Equals(_selection));
        if (!ReferenceEquals(match, _selectedRow))
        {
            _selectedRow = match;
            OnPropertyChanged(nameof(SelectedRow));
        }
    }

    private void BuildSidebarRows()
    {
        SidebarRows.Clear();
        SidebarRows.Add(new SidebarRow
        {
            Section = "Library", Glyph = SymbolMap.Glyph("tray.full.fill"),
            GlyphBrush = ColorMap.Brush("blue"), Title = "All Snippets",
            Selection = SidebarSelection.All, CountText = AllSnippetsCount.ToString()
        });
        SidebarRows.Add(new SidebarRow
        {
            Section = "Library", Glyph = SymbolMap.Glyph("flame.fill"),
            GlyphBrush = ColorMap.Brush("orange"), Title = "Frequent",
            Selection = SidebarSelection.Frequent, ShowCount = false
        });
        foreach (var c in Categories)
        {
            SidebarRows.Add(new SidebarRow
            {
                Section = "Categories", Glyph = c.Glyph, GlyphBrush = c.Brush,
                Title = c.Name, Selection = SidebarSelection.ForCategory(c),
                Category = c, CountText = c.Snippets.Count.ToString()
            });
        }
        SyncSelectedRow();
    }

    private string _searchText = "";
    public string SearchText
    {
        get => _searchText;
        set { if (Set(ref _searchText, value)) Rebuild(); }
    }

    private int _sizeLevel = 2;
    public int SizeLevel
    {
        get => _sizeLevel;
        set
        {
            var clamped = Math.Clamp(value, MinSizeLevel, MaxSizeLevel);
            if (Set(ref _sizeLevel, clamped))
            {
                OnPropertyChanged(nameof(CardWidth));
                OnPropertyChanged(nameof(CanZoomIn));
                OnPropertyChanged(nameof(CanZoomOut));
            }
        }
    }

    public double CardWidth => CardWidths[_sizeLevel];
    public bool CanZoomIn => _sizeLevel < MaxSizeLevel;
    public bool CanZoomOut => _sizeLevel > MinSizeLevel;
    public void ZoomIn() => SizeLevel += 1;
    public void ZoomOut() => SizeLevel -= 1;
    public void ResetZoom() => SizeLevel = 2;

    public int AllSnippetsCount => _allSnippets.Count;

    public bool IsAllView => _selection.Kind == SidebarKind.All;
    public bool IsReorderable => _selection.Kind is SidebarKind.All or SidebarKind.Category;
    public bool IsGrouped => Settings.Grouping != SnippetGrouping.None && IsAllView;

    public string DetailTitle => _selection.Kind switch
    {
        SidebarKind.All => "All Snippets",
        SidebarKind.Frequent => "Frequently Used",
        SidebarKind.Category => _selection.Category?.Name ?? "",
        _ => ""
    };

    // MARK: - Loading

    private List<Snippet> _allSnippets = new();

    /// <summary>Full reload from the database (after structural changes).</summary>
    public void Reload()
    {
        // Detach tracked entities so a fresh graph is loaded with current data.
        _db.ChangeTracker.Clear();

        var categories = _db.Categories.Include(c => c.Snippets)
            .OrderBy(c => c.SortIndex).ToList();
        _allSnippets = _db.Snippets.Include(s => s.Category)
            .OrderBy(s => s.SortIndex).ToList();

        // Reselect the equivalent category (same id) after a reload.
        if (_selection.Kind == SidebarKind.Category && _selection.Category != null)
        {
            var match = categories.FirstOrDefault(c => c.Id == _selection.Category.Id);
            _selection = match != null ? SidebarSelection.ForCategory(match) : SidebarSelection.All;
        }

        Categories.Clear();
        foreach (var c in categories) Categories.Add(c);

        BuildSidebarRows();

        OnPropertyChanged(nameof(AllSnippetsCount));
        OnPropertyChanged(nameof(DetailTitle));
        OnPropertyChanged(nameof(IsAllView));
        Rebuild();
    }

    /// <summary>Rebuild only the detail groups (after selection/search/grouping).</summary>
    public void Rebuild()
    {
        OnPropertyChanged(nameof(IsGrouped));
        Groups.Clear();

        var snippets = FilteredSnippets();
        if (IsGrouped)
        {
            foreach (var g in BuildGroups(snippets)) Groups.Add(g);
        }
        else
        {
            // Single headerless group carries the whole grid.
            Groups.Add(new SnippetGroup("__all__", "", "", Brushes.Gray,
                snippets, showHeader: false, collapsed: false));
        }
        OnPropertyChanged(nameof(IsEmpty));
        OnPropertyChanged(nameof(EmptyIsSearch));
        OnPropertyChanged(nameof(EmptyTitle));
        OnPropertyChanged(nameof(EmptyMessage));
        OnPropertyChanged(nameof(ShowEmptyAction));
    }

    public bool IsEmpty => FilteredSnippets().Count == 0;
    public bool EmptyIsSearch => SearchText.Trim().Length > 0;

    public string EmptyTitle => EmptyIsSearch ? "No Results"
        : _selection.Kind == SidebarKind.Frequent ? "Nothing Frequent Yet" : "No Snippets Yet";

    public string EmptyMessage => EmptyIsSearch ? $"No snippets match “{SearchText.Trim()}”."
        : _selection.Kind == SidebarKind.Frequent ? "Snippets you copy often will show up here."
        : "Add a snippet to start building your library.";

    /// <summary>The empty-state "New Snippet" button only makes sense when truly empty.</summary>
    public bool ShowEmptyAction => !EmptyIsSearch && _selection.Kind != SidebarKind.Frequent;

    private List<Snippet> FilteredSnippets()
    {
        IEnumerable<Snippet> snippets;
        switch (_selection.Kind)
        {
            case SidebarKind.All:
                snippets = _allSnippets
                    .OrderByDescending(s => s.IsPinned).ThenBy(s => s.SortIndex);
                break;
            case SidebarKind.Category:
                snippets = _allSnippets
                    .Where(s => s.CategoryId == _selection.Category?.Id)
                    .OrderByDescending(s => s.IsPinned).ThenBy(s => s.SortIndex);
                break;
            case SidebarKind.Frequent:
                snippets = _allSnippets
                    .Where(s => s.CopyCount > 0)
                    .OrderByDescending(s => s.CopyCount);
                break;
            default:
                snippets = _allSnippets;
                break;
        }

        var query = SearchText.Trim().ToLowerInvariant();
        if (query.Length > 0)
        {
            snippets = snippets.Where(s =>
                s.Title.ToLowerInvariant().Contains(query) ||
                s.Content.ToLowerInvariant().Contains(query));
        }
        return snippets.ToList();
    }

    private IEnumerable<SnippetGroup> BuildGroups(List<Snippet> snippets)
        => Settings.Grouping == SnippetGrouping.Category
            ? CategoryGroups(snippets)
            : DateGroups(snippets);

    private IEnumerable<SnippetGroup> CategoryGroups(List<Snippet> snippets)
    {
        foreach (var category in Categories)
        {
            var items = snippets.Where(s => s.CategoryId == category.Id).ToList();
            if (items.Count == 0) continue;
            var id = $"cat:{category.Name}";
            yield return new SnippetGroup(id, category.Name, category.Glyph,
                category.Brush, items, showHeader: true, collapsed: _collapsedGroups.Contains(id));
        }
        var uncategorized = snippets.Where(s => s.CategoryId == null).ToList();
        if (uncategorized.Count > 0)
        {
            yield return new SnippetGroup("uncategorized", "Uncategorized",
                SymbolMap.Glyph("tray"), Brushes.Gray, uncategorized,
                showHeader: true, collapsed: _collapsedGroups.Contains("uncategorized"));
        }
    }

    private IEnumerable<SnippetGroup> DateGroups(List<Snippet> snippets)
    {
        var now = DateTime.Now;
        var today = now.Date;
        var yesterday = today.AddDays(-1);
        var sevenDays = today.AddDays(-7);
        var thirtyDays = today.AddDays(-30);
        var startOfYear = new DateTime(today.Year, 1, 1);

        (DateTime sort, string id, string title) Bucket(DateTime date)
        {
            if (date >= today) return (today, "today", "Today");
            if (date >= yesterday) return (yesterday, "yesterday", "Yesterday");
            if (date >= sevenDays) return (sevenDays, "7d", "Previous 7 Days");
            if (date >= thirtyDays) return (thirtyDays, "30d", "Previous 30 Days");
            if (date >= startOfYear)
            {
                var monthStart = new DateTime(date.Year, date.Month, 1);
                return (monthStart, $"m{date.Year}-{date.Month}",
                    monthStart.ToString("MMMM"));
            }
            var yearStart = new DateTime(date.Year, 1, 1);
            return (yearStart, $"y{date.Year}", date.Year.ToString());
        }

        var byId = new Dictionary<string, (DateTime sort, string title, List<Snippet> items)>();
        foreach (var s in snippets)
        {
            var b = Bucket(s.CreatedAt);
            if (!byId.TryGetValue(b.id, out var entry))
                entry = (b.sort, b.title, new List<Snippet>());
            entry.items.Add(s);
            byId[b.id] = entry;
        }

        foreach (var kv in byId.OrderByDescending(e => e.Value.sort))
        {
            var items = kv.Value.items.OrderByDescending(s => s.CreatedAt);
            yield return new SnippetGroup(kv.Key, kv.Value.title, SymbolMap.Glyph("calendar"),
                Brushes.Gray, items, showHeader: true, collapsed: _collapsedGroups.Contains(kv.Key));
        }
    }

    public void ToggleGroupCollapsed(SnippetGroup group)
    {
        if (!_collapsedGroups.Remove(group.Id)) _collapsedGroups.Add(group.Id);
        group.IsCollapsed = _collapsedGroups.Contains(group.Id);
    }

    public void SetGrouping(SnippetGrouping grouping)
    {
        Settings.Grouping = grouping;
        Rebuild();
    }

    // MARK: - Snippet actions

    public void Copy(Snippet snippet)
    {
        ClipboardService.Copy(snippet.Content);
        snippet.CopyCount += 1;
        snippet.LastCopiedAt = DateTime.Now;
        _db.SaveChanges();
        // Frequent view depends on copy counts; refresh it live.
        if (_selection.Kind == SidebarKind.Frequent) Rebuild();
    }

    public void TogglePin(Snippet snippet)
    {
        snippet.IsPinned = !snippet.IsPinned;
        _db.SaveChanges();
        Rebuild();
    }

    public void Delete(Snippet snippet)
    {
        _db.Snippets.Remove(snippet);
        _db.SaveChanges();
        Reload();
    }

    public void Duplicate(Snippet snippet)
    {
        var copy = new Snippet
        {
            Title = snippet.Title.Length == 0 ? "" : snippet.Title + " Copy",
            Content = snippet.Content,
            SortIndex = snippet.SortIndex + 1,
            IsPinned = false,
            CategoryId = snippet.CategoryId,
        };
        _db.Snippets.Add(copy);
        _db.SaveChanges();
        Reload();
    }

    /// <summary>Reassign a snippet's category (null = uncategorized).</summary>
    public void MoveToCategory(Snippet snippet, Category? category)
    {
        snippet.CategoryId = category?.Id;
        _db.SaveChanges();
        Reload();
    }

    /// <summary>
    /// Persist a reordering of the currently shown snippets into sortIndex,
    /// preserving the slots of snippets filtered out of the view (parity with
    /// commitSnippetOrder in Swift).
    /// </summary>
    public void CommitOrder(IReadOnlyList<Snippet> shown)
    {
        if (shown.Count == 0) return;
        var shownIds = new HashSet<int>(shown.Select(s => s.Id));
        var iterator = shown.GetEnumerator();

        var newGlobal = new List<Snippet>();
        foreach (var s in _allSnippets)
        {
            if (shownIds.Contains(s.Id))
            {
                if (iterator.MoveNext()) newGlobal.Add(iterator.Current);
            }
            else newGlobal.Add(s);
        }

        for (var i = 0; i < newGlobal.Count; i++)
            if (newGlobal[i].SortIndex != i) newGlobal[i].SortIndex = i;

        _db.SaveChanges();
        Reload();
    }

    public void MoveCategory(Category category, int newIndex)
    {
        var ordered = Categories.ToList();
        var oldIndex = ordered.IndexOf(category);
        if (oldIndex < 0 || oldIndex == newIndex) return;
        ordered.RemoveAt(oldIndex);
        if (newIndex > oldIndex) newIndex--;
        ordered.Insert(Math.Clamp(newIndex, 0, ordered.Count), category);
        for (var i = 0; i < ordered.Count; i++)
            if (ordered[i].SortIndex != i) ordered[i].SortIndex = i;
        _db.SaveChanges();
        Reload();
    }

    // MARK: - Category actions

    public void DeleteCategory(Category category)
    {
        if (_selection.Kind == SidebarKind.Category && _selection.Category?.Id == category.Id)
            _selection = SidebarSelection.All;
        _db.Categories.Remove(category);
        _db.SaveChanges();
        Reload();
    }

    public Category DuplicateCategory(Category category)
    {
        var nextCatIndex = (Categories.Count > 0 ? Categories.Max(c => c.SortIndex) : -1) + 1;
        var copy = new Category
        {
            Name = $"{category.Name} copy",
            SymbolName = category.SymbolName,
            ColorName = category.ColorName,
            SortIndex = nextCatIndex,
        };
        _db.Categories.Add(copy);

        var nextSnippetIndex = (_allSnippets.Count > 0 ? _allSnippets.Max(s => s.SortIndex) : -1) + 1;
        foreach (var s in category.Snippets.OrderBy(s => s.SortIndex))
        {
            _db.Snippets.Add(new Snippet
            {
                Title = s.Title, Content = s.Content, SortIndex = nextSnippetIndex++,
                IsPinned = s.IsPinned, Category = copy
            });
        }
        _db.SaveChanges();
        Reload();
        return Categories.FirstOrDefault(c => c.Id == copy.Id) ?? copy;
    }

    // MARK: - Sharing & files

    public void CopyShareLink(Snippet snippet)
    {
        var cats = snippet.Category != null ? new[] { snippet.Category } : Array.Empty<Category>();
        var link = ImportExport.ImportLink(new[] { snippet }, cats);
        if (link != null) ClipboardService.Copy(link);
    }

    public void CopyShareLink(Category category)
    {
        var link = ImportExport.ImportLink(category.Snippets, new[] { category });
        if (link != null) ClipboardService.Copy(link);
    }

    public string ExportAll() => ImportExport.Export(_allSnippets, Categories);
    public string ExportCategory(Category c) => ImportExport.Export(c.Snippets, new[] { c });

    public void ImportFromJson(string json)
    {
        ImportExport.Import(_db, json, Settings.KeepImportedCategories);
        Reload();
    }
}
