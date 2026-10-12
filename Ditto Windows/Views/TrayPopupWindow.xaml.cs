using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Ditto.Models;
using Ditto.Services;
using Ditto.ViewModels;
using Microsoft.EntityFrameworkCore;

namespace Ditto.Views;

/// <summary>
/// The tray quick-copy dropdown — the Windows analogue of the macOS
/// MenuBarExtra. Search, then click a snippet to copy it and dismiss.
/// </summary>
public partial class TrayPopupWindow : Window
{
    private readonly MainViewModel _vm;
    private readonly ObservableCollection<SnippetGroup> _groups = new();

    public TrayPopupWindow(MainViewModel vm)
    {
        InitializeComponent();
        _vm = vm;
        GroupsList.ItemsSource = _groups;
    }

    public void ShowNearTray()
    {
        Rebuild();
        // Anchor to the bottom-right of the work area, just above the taskbar.
        var area = SystemParameters.WorkArea;
        Left = area.Right - Width - 8;
        Top = area.Bottom - Height - 8;
        Show();
        Activate();
        SearchBox.Text = "";
        SearchBox.Focus();
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e) => Rebuild();

    private void Rebuild()
    {
        _groups.Clear();
        var settings = _vm.Settings;

        var all = _vm.Db.Snippets.Include(s => s.Category).OrderBy(s => s.SortIndex).ToList();
        var categories = _vm.Db.Categories.OrderBy(c => c.SortIndex).ToList();

        var query = SearchBox.Text.Trim().ToLowerInvariant();
        bool Matches(Snippet s) => query.Length == 0
            || s.Title.ToLowerInvariant().Contains(query)
            || s.Content.ToLowerInvariant().Contains(query);

        bool Expanded(string title) => query.Length > 0 || !settings.CollapsedSections.Contains(title);

        // Frequently Used (only when not searching).
        if (query.Length == 0)
        {
            var frequent = all.Where(s => s.CopyCount > 0)
                .OrderByDescending(s => s.CopyCount).Take(5).ToList();
            if (frequent.Count > 0)
                _groups.Add(new SnippetGroup("Frequently Used", "Frequently Used",
                    SymbolMap.Glyph("flame.fill"), Brushes.Gray, frequent,
                    showHeader: true, collapsed: !Expanded("Frequently Used")));
        }

        foreach (var category in categories)
        {
            var items = all.Where(s => s.CategoryId == category.Id && Matches(s)).ToList();
            if (items.Count == 0) continue;
            _groups.Add(new SnippetGroup(category.Name, category.Name, category.Glyph,
                category.Brush, items, showHeader: true, collapsed: !Expanded(category.Name)));
        }

        var uncategorized = all.Where(s => s.CategoryId == null && Matches(s)).ToList();
        if (uncategorized.Count > 0)
            _groups.Add(new SnippetGroup("Uncategorized", "Uncategorized", SymbolMap.Glyph("tray"),
                Brushes.Gray, uncategorized, showHeader: true, collapsed: !Expanded("Uncategorized")));

        EmptyLabel.Text = SearchBox.Text.Trim().Length == 0 ? "No snippets yet" : "No matches";
        EmptyLabel.Visibility = _groups.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void GroupHeader_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is SnippetGroup group)
        {
            _vm.Settings.ToggleSection(group.Title);
            Rebuild();
        }
    }

    private void Row_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is Snippet snippet)
        {
            _vm.Copy(snippet);
            Hide();
        }
    }

    private void OpenMain_Click(object sender, RoutedEventArgs e)
    {
        Hide();
        App.Current.ShowMainWindow();
    }

    private void Settings_Click(object sender, RoutedEventArgs e)
    {
        Hide();
        new SettingsWindow(_vm.Settings).ShowDialog();
    }

    private void Quit_Click(object sender, RoutedEventArgs e) => App.Current.QuitApp();

    private void Window_Deactivated(object sender, EventArgs e) => Hide();
}
