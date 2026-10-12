using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using Ditto.Models;
using Ditto.ViewModels;

namespace Ditto.Views;

public partial class CategoryEditorWindow : Window
{
    private readonly MainViewModel _vm;
    private readonly Category? _category;

    private string _colorName = "blue";
    private string _symbolName = "tag.fill";

    private readonly Dictionary<string, Border> _colorSwatches = new();
    private readonly Dictionary<string, Border> _iconTiles = new();

    public CategoryEditorWindow(MainViewModel vm, Category? category)
    {
        InitializeComponent();
        _vm = vm;
        _category = category;

        var editing = category != null;
        Title = editing ? "Edit Category" : "New Category";
        SaveButton.Content = editing ? "Save" : "Add";

        if (editing)
        {
            NameBox.Text = category!.Name;
            _colorName = category.ColorName;
            _symbolName = category.SymbolName;
        }

        BuildColorSwatches();
        BuildIconTiles();
        RefreshPreview();

        NameBox.TextChanged += (_, _) => SaveButton.IsEnabled = NameBox.Text.Trim().Length > 0;
        SaveButton.IsEnabled = NameBox.Text.Trim().Length > 0;
        Loaded += (_, _) => NameBox.Focus();
    }

    private void BuildColorSwatches()
    {
        foreach (var name in ColorMap.Names)
        {
            var ring = new Border
            {
                Width = 36, Height = 36, Margin = new Thickness(4),
                CornerRadius = new CornerRadius(18),
                BorderThickness = new Thickness(0),
                BorderBrush = Brushes.Black,
                Child = new Ellipse
                {
                    Width = 28, Height = 28,
                    Fill = ColorMap.Brush(name),
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                },
                Cursor = System.Windows.Input.Cursors.Hand,
            };
            var captured = name;
            ring.MouseLeftButtonUp += (_, _) => { _colorName = captured; RefreshPreview(); };
            _colorSwatches[name] = ring;
            ColorList.Items.Add(ring);
        }
    }

    private void BuildIconTiles()
    {
        foreach (var symbol in SymbolMap.CategoryOptions)
        {
            var tile = new Border
            {
                Width = 40, Height = 40, Margin = new Thickness(4),
                CornerRadius = new CornerRadius(9),
                Cursor = System.Windows.Input.Cursors.Hand,
                Child = new TextBlock
                {
                    Text = SymbolMap.Glyph(symbol),
                    FontFamily = new FontFamily(SymbolMap.FontFamily),
                    FontSize = 16,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                },
            };
            var captured = symbol;
            tile.MouseLeftButtonUp += (_, _) => { _symbolName = captured; RefreshPreview(); };
            _iconTiles[symbol] = tile;
            IconList.Items.Add(tile);
        }
    }

    private void RefreshPreview()
    {
        var accent = ColorMap.Color(_colorName);
        var accentBrush = new SolidColorBrush(accent);
        var faint = new SolidColorBrush(Color.FromArgb(31, accent.R, accent.G, accent.B));

        PreviewIcon.Text = SymbolMap.Glyph(_symbolName);
        PreviewIcon.Foreground = accentBrush;

        foreach (var (name, ring) in _colorSwatches)
            ring.BorderThickness = new Thickness(name == _colorName ? 2.5 : 0);

        foreach (var (symbol, tile) in _iconTiles)
        {
            var selected = symbol == _symbolName;
            tile.Background = selected ? accentBrush : faint;
            if (tile.Child is TextBlock tb)
                tb.Foreground = selected ? Brushes.White : accentBrush;
        }
    }

    private void Cancel_Click(object sender, RoutedEventArgs e) => Close();

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        var name = NameBox.Text.Trim();
        if (name.Length == 0) return;

        if (_category != null)
        {
            _category.Name = name;
            _category.SymbolName = _symbolName;
            _category.ColorName = _colorName;
        }
        else
        {
            var nextIndex = (_vm.Db.Categories.Any() ? _vm.Db.Categories.Max(c => c.SortIndex) : -1) + 1;
            _vm.Db.Categories.Add(new Category
            {
                Name = name, SymbolName = _symbolName, ColorName = _colorName, SortIndex = nextIndex,
            });
        }

        _vm.Db.SaveChanges();
        _vm.Reload();
        Close();
    }
}
