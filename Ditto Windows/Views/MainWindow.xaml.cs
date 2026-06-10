using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Ditto.Models;
using Ditto.ViewModels;

namespace Ditto.Views;

public partial class MainWindow : Window
{
    private Point _dragStart;
    private Snippet? _pressedSnippet;
    private bool _isDragging;

    public MainWindow()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        // Group the sidebar into "Library" / "Categories" sections. Done here
        // (not via a CollectionViewSource resource) so the bound collection is
        // already resolved against the window's DataContext.
        var view = System.Windows.Data.CollectionViewSource.GetDefaultView(Vm.SidebarRows);
        if (view != null && view.GroupDescriptions.Count == 0)
            view.GroupDescriptions.Add(new System.Windows.Data.PropertyGroupDescription("Section"));
        SearchBox?.Focus();
    }

    private MainViewModel Vm => (MainViewModel)DataContext;

    // MARK: - Card interactions

    private void Card_MouseDown(object sender, MouseButtonEventArgs e)
    {
        _dragStart = e.GetPosition(this);
        _pressedSnippet = (sender as FrameworkElement)?.DataContext as Snippet;
        _isDragging = false;
    }

    private void Card_MouseMove(object sender, MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed || _pressedSnippet == null) return;
        var p = e.GetPosition(this);
        if (Math.Abs(p.X - _dragStart.X) < SystemParameters.MinimumHorizontalDragDistance &&
            Math.Abs(p.Y - _dragStart.Y) < SystemParameters.MinimumVerticalDragDistance)
            return;

        _isDragging = true;
        DragDrop.DoDragDrop((DependencyObject)sender, _pressedSnippet, DragDropEffects.Move);
        _isDragging = false;
        _pressedSnippet = null;
    }

    private void Card_Click(object sender, MouseButtonEventArgs e)
    {
        if (_isDragging) { _isDragging = false; return; }
        if ((sender as FrameworkElement)?.DataContext is not Snippet snippet) return;
        Vm.Copy(snippet);
        ShowCopiedOverlay(sender as Border);
    }

    private void Card_DragOver(object sender, DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent(typeof(Snippet)) ? DragDropEffects.Move : DragDropEffects.None;
        e.Handled = true;
    }

    private void Card_Drop(object sender, DragEventArgs e)
    {
        if (e.Data.GetData(typeof(Snippet)) is not Snippet dragged) return;
        if ((sender as FrameworkElement)?.DataContext is not Snippet target) return;
        if (ReferenceEquals(dragged, target) || !Vm.IsReorderable) return;

        // Reorder only within the same group (same category section / the single
        // ungrouped grid). Cross-category moves are done by dropping on the sidebar.
        var group = Vm.Groups.FirstOrDefault(g => g.Snippets.Contains(target));
        if (group == null || !group.Snippets.Contains(dragged)) return;

        var from = group.Snippets.IndexOf(dragged);
        var to = group.Snippets.IndexOf(target);
        group.Snippets.Move(from, to);
        Vm.CommitOrder(group.Snippets.ToList());
        e.Handled = true;
    }

    private void ShowCopiedOverlay(Border? card)
    {
        if (card == null) return;
        var overlay = FindChild<Border>(card, "copied");
        if (overlay == null) return;

        overlay.Visibility = Visibility.Visible;
        overlay.BeginAnimation(OpacityProperty,
            new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(150)));

        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(900) };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            var fade = new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(250));
            fade.Completed += (_, _) => overlay.Visibility = Visibility.Collapsed;
            overlay.BeginAnimation(OpacityProperty, fade);
        };
        timer.Start();
    }

    // MARK: - Card context menu

    private Snippet? MenuSnippet(object sender)
        => (sender as FrameworkElement)?.DataContext as Snippet;

    private void Ctx_Copy(object sender, RoutedEventArgs e)
    {
        if (MenuSnippet(sender) is { } s) Vm.Copy(s);
    }

    private void Ctx_Edit(object sender, RoutedEventArgs e)
    {
        if (MenuSnippet(sender) is { } s) EditSnippet(s);
    }

    private void Ctx_Duplicate(object sender, RoutedEventArgs e)
    {
        if (MenuSnippet(sender) is { } s) Vm.Duplicate(s);
    }

    private void Ctx_ShareLink(object sender, RoutedEventArgs e)
    {
        if (MenuSnippet(sender) is { } s) Vm.CopyShareLink(s);
    }

    private void Ctx_TogglePin(object sender, RoutedEventArgs e)
    {
        if (MenuSnippet(sender) is { } s) Vm.TogglePin(s);
    }

    private void Ctx_OpenLink(object sender, RoutedEventArgs e)
    {
        if (MenuSnippet(sender)?.UrlValue is { } url)
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url.ToString()) { UseShellExecute = true });
    }

    private void Ctx_Delete(object sender, RoutedEventArgs e)
    {
        if (MenuSnippet(sender) is { } s) Vm.Delete(s);
    }

    // MARK: - Sidebar drop (refile / uncategorize)

    private void Sidebar_DragOver(object sender, DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent(typeof(Snippet)) ? DragDropEffects.Move : DragDropEffects.None;
        e.Handled = true;
    }

    private void Sidebar_Drop(object sender, DragEventArgs e)
    {
        if (e.Data.GetData(typeof(Snippet)) is not Snippet dragged) return;
        if (RowUnderPointer(e) is not { } row) return;

        if (row.Selection.Kind == SidebarKind.Category)
            Vm.MoveToCategory(dragged, row.Category);
        else if (row.Selection.Kind == SidebarKind.All)
            Vm.MoveToCategory(dragged, null); // uncategorize
        e.Handled = true;
    }

    private SidebarRow? RowUnderPointer(DragEventArgs e)
    {
        var element = SidebarList.InputHitTest(e.GetPosition(SidebarList)) as DependencyObject;
        while (element != null && element is not ListBoxItem)
            element = VisualTreeHelper.GetParent(element);
        return (element as ListBoxItem)?.DataContext as SidebarRow;
    }

    // MARK: - Sidebar category context menu

    private Category? RowCategory(object sender)
        => ((sender as FrameworkElement)?.DataContext as SidebarRow)?.Category;

    private void SidebarCtx_Opening(object sender, ContextMenuEventArgs e)
    {
        // Only category rows get a context menu; suppress it for All / Frequent.
        if ((sender as FrameworkElement)?.DataContext is SidebarRow { Category: null })
            e.Handled = true;
    }

    private void SidebarCtx_Edit(object sender, RoutedEventArgs e)
    {
        if (RowCategory(sender) is { } c) EditCategory(c);
    }

    private void SidebarCtx_Duplicate(object sender, RoutedEventArgs e)
    {
        if (RowCategory(sender) is { } c) Vm.DuplicateCategory(c);
    }

    private void SidebarCtx_ShareLink(object sender, RoutedEventArgs e)
    {
        if (RowCategory(sender) is { } c) Vm.CopyShareLink(c);
    }

    private void SidebarCtx_Export(object sender, RoutedEventArgs e)
    {
        if (RowCategory(sender) is not { } c) return;
        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            Filter = "Ditto Library (*.json)|*.json",
            FileName = $"Ditto - {c.Name}.json",
        };
        if (dialog.ShowDialog(this) == true)
            System.IO.File.WriteAllText(dialog.FileName, Vm.ExportCategory(c));
    }

    private void SidebarCtx_Delete(object sender, RoutedEventArgs e)
    {
        if (RowCategory(sender) is { } c) Vm.DeleteCategory(c);
    }

    // MARK: - Group header collapse

    private void GroupHeader_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is SnippetGroup group)
            Vm.ToggleGroupCollapsed(group);
    }

    // MARK: - Toolbar

    private void NewSnippet_Click(object sender, RoutedEventArgs e) => CreateSnippet();
    private void NewCategory_Click(object sender, RoutedEventArgs e) => CreateCategory();
    private void ZoomIn_Click(object sender, RoutedEventArgs e) => Vm.ZoomIn();
    private void ZoomOut_Click(object sender, RoutedEventArgs e) => Vm.ZoomOut();

    private void GroupBy_Click(object sender, RoutedEventArgs e)
    {
        if (GroupByMenu == null) return;
        // Reflect current selection as checks.
        ((MenuItem)GroupByMenu.Items[0]).IsChecked = Vm.Settings.Grouping == SnippetGrouping.None;
        ((MenuItem)GroupByMenu.Items[1]).IsChecked = Vm.Settings.Grouping == SnippetGrouping.Category;
        ((MenuItem)GroupByMenu.Items[2]).IsChecked = Vm.Settings.Grouping == SnippetGrouping.DateAdded;
        GroupByMenu.PlacementTarget = GroupByButton;
        GroupByMenu.IsOpen = true;
    }

    private void Group_None(object sender, RoutedEventArgs e) => Vm.SetGrouping(SnippetGrouping.None);
    private void Group_Category(object sender, RoutedEventArgs e) => Vm.SetGrouping(SnippetGrouping.Category);
    private void Group_Date(object sender, RoutedEventArgs e) => Vm.SetGrouping(SnippetGrouping.DateAdded);

    // MARK: - Menu bar

    private void Menu_Export(object sender, RoutedEventArgs e) => ExportLibrary();
    private void Menu_Import(object sender, RoutedEventArgs e) => ImportLibrary();
    private void Menu_DefaultSize(object sender, RoutedEventArgs e) => Vm.ResetZoom();
    private void Menu_Quit(object sender, RoutedEventArgs e) => App.Current.QuitApp();

    private void Menu_Settings(object sender, RoutedEventArgs e)
        => new SettingsWindow(Vm.Settings) { Owner = this }.ShowDialog();

    private void Menu_Help(object sender, RoutedEventArgs e)
        => MessageBox.Show(this,
            "Click any card to copy it to the clipboard.\n\n" +
            "• Drag a card to reorder it, or drop it onto a category in the sidebar to refile it.\n" +
            "• Right-click a card to edit, duplicate, pin, share, or delete it.\n" +
            "• Use the tray icon for quick copying without opening the window.\n" +
            "• Share snippets via File ▸ Export, or by copying a share link from the right-click menu.",
            "Ditto Help", MessageBoxButton.OK, MessageBoxImage.Information);

    private void Menu_About(object sender, RoutedEventArgs e)
        => MessageBox.Show(this,
            "Ditto for Windows\nA colorful home for the text you copy all the time.\n\nVersion 1.0",
            "About Ditto", MessageBoxButton.OK, MessageBoxImage.Information);

    // MARK: - Editors

    private void CreateSnippet()
    {
        var cat = Vm.Selection.Kind == SidebarKind.Category ? Vm.Selection.Category : null;
        new SnippetEditorWindow(Vm, null, cat) { Owner = this }.ShowDialog();
    }

    private void EditSnippet(Snippet snippet)
        => new SnippetEditorWindow(Vm, snippet) { Owner = this }.ShowDialog();

    private void CreateCategory()
        => new CategoryEditorWindow(Vm, null) { Owner = this }.ShowDialog();

    public void EditCategory(Category category)
        => new CategoryEditorWindow(Vm, category) { Owner = this }.ShowDialog();

    // MARK: - Keyboard shortcuts

    protected override void OnPreviewKeyDown(KeyEventArgs e)
    {
        base.OnPreviewKeyDown(e);
        var ctrl = (Keyboard.Modifiers & ModifierKeys.Control) != 0;
        var shift = (Keyboard.Modifiers & ModifierKeys.Shift) != 0;
        if (!ctrl) return;

        switch (e.Key)
        {
            case Key.N when shift: CreateCategory(); e.Handled = true; break;
            case Key.N: CreateSnippet(); e.Handled = true; break;
            case Key.OemPlus or Key.Add: Vm.ZoomIn(); e.Handled = true; break;
            case Key.OemMinus or Key.Subtract: Vm.ZoomOut(); e.Handled = true; break;
            case Key.E when shift: ExportLibrary(); e.Handled = true; break;
            case Key.OemComma: new SettingsWindow(Vm.Settings) { Owner = this }.ShowDialog(); e.Handled = true; break;
        }
    }

    // MARK: - Import / export

    public void ExportLibrary()
    {
        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            Filter = "Ditto Library (*.json)|*.json",
            FileName = $"Ditto Library {DateTime.Now:yyyy-MM-dd}.json",
        };
        if (dialog.ShowDialog(this) == true)
            System.IO.File.WriteAllText(dialog.FileName, Vm.ExportAll());
    }

    public void ImportLibrary()
    {
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Filter = "Ditto Library (*.json)|*.json",
        };
        if (dialog.ShowDialog(this) == true)
        {
            try { Vm.ImportFromJson(System.IO.File.ReadAllText(dialog.FileName)); }
            catch (Exception ex) { MessageBox.Show(this, ex.Message, "Import failed"); }
        }
    }

    // MARK: - Visual tree helper

    private static T? FindChild<T>(DependencyObject parent, string name) where T : FrameworkElement
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
        {
            var child = VisualTreeHelper.GetChild(parent, i);
            if (child is T fe && fe.Name == name) return fe;
            if (FindChild<T>(child, name) is { } found) return found;
        }
        return null;
    }
}
