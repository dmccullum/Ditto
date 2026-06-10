using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace Ditto.Converters;

/// <summary>true -> Visible, false -> Collapsed. Pass "Invert" to reverse.</summary>
public sealed class BoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type t, object? p, CultureInfo c)
    {
        var b = value is true;
        if (p as string == "Invert") b = !b;
        return b ? Visibility.Visible : Visibility.Collapsed;
    }
    public object ConvertBack(object value, Type t, object? p, CultureInfo c)
        => value is Visibility.Visible;
}

/// <summary>Non-null / non-empty -> Visible, otherwise Collapsed.</summary>
public sealed class NotEmptyToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type t, object? p, CultureInfo c)
    {
        var visible = value switch
        {
            null => false,
            string s => s.Length > 0,
            int i => i > 0,
            _ => true
        };
        if (p as string == "Invert") visible = !visible;
        return visible ? Visibility.Visible : Visibility.Collapsed;
    }
    public object ConvertBack(object value, Type t, object? p, CultureInfo c)
        => Binding.DoNothing;
}

/// <summary>Collapsed group chevron: false -> 90°, true(collapsed) -> 0°.</summary>
public sealed class CollapsedToAngleConverter : IValueConverter
{
    public object Convert(object value, Type t, object? p, CultureInfo c)
        => value is true ? 0.0 : 90.0;
    public object ConvertBack(object value, Type t, object? p, CultureInfo c)
        => Binding.DoNothing;
}

/// <summary>Inverts a boolean.</summary>
public sealed class InverseBoolConverter : IValueConverter
{
    public object Convert(object value, Type t, object? p, CultureInfo c) => value is not true;
    public object ConvertBack(object value, Type t, object? p, CultureInfo c) => value is not true;
}
