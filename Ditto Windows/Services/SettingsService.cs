using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using Ditto.Models;

namespace Ditto.Services;

/// <summary>
/// UserDefaults analogue: persists preferences to %APPDATA%\Ditto\settings.json.
/// Implements INotifyPropertyChanged via ObservableObject so the settings and
/// menu-bar views bind to it directly (parity with AppSettings.swift).
/// </summary>
public sealed class SettingsService : ObservableObject
{
    private static string FilePath => Path.Combine(
        Path.GetDirectoryName(DittoDbContext.DatabasePath)!, "settings.json");

    // Section titles the user has collapsed in the tray dropdown.
    public HashSet<string> CollapsedSections { get; set; } = new();

    private SnippetGrouping _grouping = SnippetGrouping.None;
    public SnippetGrouping Grouping { get => _grouping; set { if (Set(ref _grouping, value)) Save(); } }

    private LinkCategoryBehavior _linkCategoryBehavior = LinkCategoryBehavior.Keep;
    public LinkCategoryBehavior LinkCategoryBehavior
    {
        get => _linkCategoryBehavior;
        set { if (Set(ref _linkCategoryBehavior, value)) Save(); }
    }

    public bool KeepImportedCategories => LinkCategoryBehavior == LinkCategoryBehavior.Keep;

    [JsonIgnore] private bool _loaded;

    public static SettingsService Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                var loaded = JsonSerializer.Deserialize<SettingsService>(File.ReadAllText(FilePath));
                if (loaded != null) { loaded._loaded = true; return loaded; }
            }
        }
        catch { /* fall through to defaults */ }
        return new SettingsService { _loaded = true };
    }

    public void Save()
    {
        if (!_loaded) return; // don't persist during construction/deserialization
        try
        {
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this,
                new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { /* best effort */ }
    }

    public void ToggleSection(string title)
    {
        if (!CollapsedSections.Remove(title)) CollapsedSections.Add(title);
        Save();
    }
}
