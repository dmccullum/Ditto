using System.Windows;
using System.Windows.Controls;
using Ditto.Models;
using Ditto.ViewModels;

namespace Ditto.Views;

public partial class SnippetEditorWindow : Window
{
    private readonly MainViewModel _vm;
    private readonly Snippet? _snippet;

    /// <summary>A category choice for the dropdown; null Category means "None".</summary>
    private sealed record CategoryChoice(Category? Category)
    {
        public string Display => Category?.Name ?? "None";
        public override string ToString() => Display;
    }

    public SnippetEditorWindow(MainViewModel vm, Snippet? snippet,
                               Category? defaultCategory = null, string defaultContent = "")
    {
        InitializeComponent();
        _vm = vm;
        _snippet = snippet;

        var editing = snippet != null;
        Title = editing ? "Edit Snippet" : "New Snippet";
        HeaderText.Text = Title;
        SaveButton.Content = editing ? "Save" : "Add";

        // Build category choices: None first, then categories in order.
        var choices = new List<CategoryChoice> { new(null) };
        choices.AddRange(vm.Categories.Select(c => new CategoryChoice(c)));
        CategoryCombo.ItemsSource = choices;

        if (editing)
        {
            ContentBox.Text = snippet!.Content;
            NameBox.Text = snippet.Title;
            CategoryCombo.SelectedItem = choices.FirstOrDefault(c => c.Category?.Id == snippet.CategoryId) ?? choices[0];
        }
        else
        {
            ContentBox.Text = defaultContent;
            CategoryCombo.SelectedItem = choices.FirstOrDefault(c => c.Category?.Id == defaultCategory?.Id) ?? choices[0];
        }

        UpdateCharCount();
        Loaded += (_, _) =>
        {
            if (ContentBox.Text.Length == 0) ContentBox.Focus();
            else { NameBox.Focus(); NameBox.SelectAll(); }
        };
    }

    private void ContentBox_TextChanged(object sender, TextChangedEventArgs e) => UpdateCharCount();

    private void UpdateCharCount()
    {
        if (CharCount != null) CharCount.Text = $"{ContentBox.Text.Length} characters";
        if (SaveButton != null) SaveButton.IsEnabled = ContentBox.Text.Trim().Length > 0;
    }

    private void Cancel_Click(object sender, RoutedEventArgs e) => Close();

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        var content = ContentBox.Text;
        if (content.Trim().Length == 0) return;

        var category = (CategoryCombo.SelectedItem as CategoryChoice)?.Category;

        if (_snippet != null)
        {
            _snippet.Title = NameBox.Text;
            _snippet.Content = content;
            _snippet.CategoryId = category?.Id;
        }
        else
        {
            // Append after the current highest slot so it lands at the end.
            var nextIndex = (_vm.Db.Snippets.Any() ? _vm.Db.Snippets.Max(s => s.SortIndex) : -1) + 1;
            _vm.Db.Snippets.Add(new Snippet
            {
                Title = NameBox.Text,
                Content = content,
                CategoryId = category?.Id,
                SortIndex = nextIndex,
            });
        }

        _vm.Db.SaveChanges();
        _vm.Reload();
        Close();
    }
}
