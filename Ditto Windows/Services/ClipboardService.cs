using System.Windows;

namespace Ditto.Services;

/// <summary>Thin wrapper over the Windows clipboard (parity with Clipboard.swift).</summary>
public static class ClipboardService
{
    public static void Copy(string text)
    {
        // The clipboard is a shared system resource and can briefly be locked by
        // another process; retry a few times before giving up.
        for (var attempt = 0; attempt < 5; attempt++)
        {
            try
            {
                Clipboard.SetText(text ?? "");
                return;
            }
            catch
            {
                Thread.Sleep(40);
            }
        }
    }
}
