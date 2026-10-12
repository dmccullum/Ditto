using System.Drawing;
using System.Windows;
using Ditto.Models;
using Ditto.Services;
using Ditto.ViewModels;
using Ditto.Views;
using WinForms = System.Windows.Forms;

namespace Ditto;

public partial class App : Application
{
    private SingleInstance _instance = null!;
    private DittoDbContext _db = null!;
    private SettingsService _settings = null!;
    private MainViewModel _vm = null!;
    private WinForms.NotifyIcon _tray = null!;
    private MainWindow? _main;
    private TrayPopupWindow? _popup;

    public static new App Current => (App)Application.Current;
    public MainViewModel ViewModel => _vm;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var argument = e.Args.FirstOrDefault(a => a.StartsWith("ditto:", StringComparison.OrdinalIgnoreCase));
        var startInTray = e.Args.Contains("--tray");

        _instance = new SingleInstance();
        if (!_instance.IsFirstInstance)
        {
            // Hand any ditto:// link to the already-running app, then exit.
            if (argument != null) SingleInstance.Signal(argument);
            else SingleInstance.Signal("--activate");
            Shutdown();
            return;
        }

        _instance.MessageReceived += OnMessageFromOtherInstance;
        _instance.StartServer();

        // Data layer.
        _db = new DittoDbContext();
        _db.Database.EnsureCreated();
        SampleData.SeedIfNeeded(_db);

        _settings = SettingsService.Load();
        _vm = new MainViewModel(_db, _settings);

        UrlScheme.EnsureRegistered();
        SetUpTray();

        // A ditto:// link on launch is handled before showing any window.
        if (argument != null)
        {
            DittoUrl.Handle(argument, _db, _settings.KeepImportedCategories);
            _vm.Reload();
        }

        if (!startInTray) ShowMainWindow();
    }

    // MARK: - Windows

    public void ShowMainWindow()
    {
        if (_main == null)
        {
            _main = new MainWindow { DataContext = _vm };
            _main.Closed += (_, _) => _main = null;
        }
        _main.Show();
        if (_main.WindowState == WindowState.Minimized) _main.WindowState = WindowState.Normal;
        _main.Activate();
    }

    private void ToggleTrayPopup()
    {
        if (_popup is { IsVisible: true })
        {
            _popup.Hide();
            return;
        }
        _popup ??= new TrayPopupWindow(_vm);
        _popup.ShowNearTray();
    }

    // MARK: - Tray icon

    private void SetUpTray()
    {
        _tray = new WinForms.NotifyIcon
        {
            Icon = TrayIcon.Create(),
            Text = "Ditto",
            Visible = true,
        };

        var menu = new WinForms.ContextMenuStrip();
        menu.Items.Add("Open Ditto", null, (_, _) => Dispatcher.Invoke(ShowMainWindow));
        menu.Items.Add(new WinForms.ToolStripSeparator());
        menu.Items.Add("Quit Ditto", null, (_, _) => Dispatcher.Invoke(QuitApp));
        _tray.ContextMenuStrip = menu;

        _tray.MouseClick += (_, args) =>
        {
            if (args.Button == WinForms.MouseButtons.Left)
                Dispatcher.Invoke(ToggleTrayPopup);
        };
        _tray.DoubleClick += (_, _) => Dispatcher.Invoke(ShowMainWindow);
    }

    private void OnMessageFromOtherInstance(string message)
    {
        Dispatcher.Invoke(() =>
        {
            if (message.StartsWith("ditto:", StringComparison.OrdinalIgnoreCase))
            {
                DittoUrl.Handle(message, _db, _settings.KeepImportedCategories);
                _vm.Reload();
            }
            ShowMainWindow();
        });
    }

    public void QuitApp()
    {
        _tray.Visible = false;
        _tray.Dispose();
        _instance.Dispose();
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        try { _tray?.Dispose(); } catch { }
        base.OnExit(e);
    }
}

/// <summary>Draws a simple tray icon at runtime (no .ico asset needed).</summary>
internal static class TrayIcon
{
    public static Icon Create()
    {
        using var bmp = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);
            using var bg = new SolidBrush(ColorTranslator.FromHtml("#007AFF"));
            g.FillRoundedRectangle(bg, new Rectangle(2, 2, 28, 28), 7);
            using var font = new Font("Segoe UI", 15, System.Drawing.FontStyle.Bold, GraphicsUnit.Pixel);
            using var fg = new SolidBrush(Color.White);
            var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
            g.DrawString("D", font, fg, new RectangleF(2, 1, 28, 28), sf);
        }
        return Icon.FromHandle(bmp.GetHicon());
    }
}

/// <summary>Small GDI+ helper for the rounded tray square.</summary>
internal static class GraphicsExtensions
{
    public static void FillRoundedRectangle(this Graphics g, Brush brush, Rectangle r, int radius)
    {
        using var path = new System.Drawing.Drawing2D.GraphicsPath();
        var d = radius * 2;
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        g.FillPath(brush, path);
    }
}
