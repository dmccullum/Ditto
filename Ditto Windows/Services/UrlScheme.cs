using Microsoft.Win32;

namespace Ditto.Services;

/// <summary>
/// Registers the ditto:// URL scheme under HKCU so links open this app. This is
/// the Windows analogue of the CFBundleURLTypes entry the Apple apps declare.
/// Registration is per-user, so it needs no admin rights.
/// </summary>
public static class UrlScheme
{
    public static void EnsureRegistered()
    {
        try
        {
            var exe = Environment.ProcessPath;
            if (string.IsNullOrEmpty(exe)) return;

            using var root = Registry.CurrentUser.CreateSubKey(@"Software\Classes\ditto");
            if (root == null) return;
            // Only rewrite if missing or pointing elsewhere (e.g. app moved).
            var command = $"\"{exe}\" \"%1\"";
            using var existing = root.OpenSubKey(@"shell\open\command");
            if (existing?.GetValue("") as string == command) return;

            root.SetValue("", "URL:Ditto Protocol");
            root.SetValue("URL Protocol", "");
            using var icon = root.CreateSubKey("DefaultIcon");
            icon?.SetValue("", $"\"{exe}\",0");
            using var cmd = root.CreateSubKey(@"shell\open\command");
            cmd?.SetValue("", command);
        }
        catch { /* best effort */ }
    }
}
