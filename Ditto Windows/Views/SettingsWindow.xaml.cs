using System.Windows;
using System.Windows.Controls;
using Ditto.Models;
using Ditto.Services;

namespace Ditto.Views;

public partial class SettingsWindow : Window
{
    private readonly SettingsService _settings;
    private bool _loading = true;

    private sealed record BehaviorChoice(LinkCategoryBehavior Value)
    {
        public string Display => Value.Label();
        public override string ToString() => Display;
    }

    public SettingsWindow(SettingsService settings)
    {
        InitializeComponent();
        _settings = settings;

        LaunchAtLogin.IsChecked = LoginItem.IsEnabled;

        var choices = new[]
        {
            new BehaviorChoice(LinkCategoryBehavior.Keep),
            new BehaviorChoice(LinkCategoryBehavior.Uncategorized),
        };
        LinkBehavior.ItemsSource = choices;
        LinkBehavior.SelectedItem = choices.First(c => c.Value == settings.LinkCategoryBehavior);

        _loading = false;
    }

    private void LaunchAtLogin_Changed(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        LoginItem.SetEnabled(LaunchAtLogin.IsChecked == true);
    }

    private void LinkBehavior_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_loading) return;
        if (LinkBehavior.SelectedItem is BehaviorChoice choice)
            _settings.LinkCategoryBehavior = choice.Value;
    }
}
