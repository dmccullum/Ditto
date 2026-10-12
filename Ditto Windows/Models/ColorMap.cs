using System.Windows.Media;

namespace Ditto.Models;

/// <summary>
/// The 12-color palette, resolved from the stored color *name* (kept identical
/// to SnippetColor.swift so exports round-trip). Hex values approximate Apple's
/// system colors so cards look familiar across platforms.
/// </summary>
public static class ColorMap
{
    public static readonly string[] Names =
    {
        "red", "orange", "yellow", "green", "mint", "teal",
        "cyan", "blue", "indigo", "purple", "pink", "brown"
    };

    private static readonly Dictionary<string, Color> _colors = new()
    {
        ["red"]    = Hex("#FF3B30"),
        ["orange"] = Hex("#FF9500"),
        ["yellow"] = Hex("#FFCC00"),
        ["green"]  = Hex("#34C759"),
        ["mint"]   = Hex("#00C7BE"),
        ["teal"]   = Hex("#00858F"),
        ["cyan"]   = Hex("#32ADE6"),
        ["blue"]   = Hex("#007AFF"),
        ["indigo"] = Hex("#5856D6"),
        ["purple"] = Hex("#AF52DE"),
        ["pink"]   = Hex("#FF2D55"),
        ["brown"]  = Hex("#A2845E"),
    };

    public static Color Color(string name)
        => _colors.TryGetValue(name, out var c) ? c : _colors["blue"];

    public static Brush Brush(string name)
    {
        var b = new SolidColorBrush(Color(name));
        b.Freeze();
        return b;
    }

    /// <summary>A soft diagonal wash used as a snippet card's background.</summary>
    public static Brush CardBackground(string name)
    {
        var c = Color(name);
        var brush = new LinearGradientBrush
        {
            StartPoint = new System.Windows.Point(0, 0),
            EndPoint = new System.Windows.Point(1, 1),
        };
        brush.GradientStops.Add(new GradientStop(WithAlpha(c, 0.16), 0));
        brush.GradientStops.Add(new GradientStop(WithAlpha(c, 0.04), 1));
        brush.Freeze();
        return brush;
    }

    public static Brush CardBorder(string name)
    {
        var b = new SolidColorBrush(WithAlpha(Color(name), 0.30));
        b.Freeze();
        return b;
    }

    private static Color WithAlpha(Color c, double a)
        => System.Windows.Media.Color.FromArgb((byte)(a * 255), c.R, c.G, c.B);

    public static string DisplayName(string name)
        => name.Length == 0 ? name : char.ToUpper(name[0]) + name[1..];

    private static Color Hex(string hex)
        => (Color)ColorConverter.ConvertFromString(hex)!;
}
