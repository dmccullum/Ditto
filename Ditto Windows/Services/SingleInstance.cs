using System.IO;
using System.IO.Pipes;

namespace Ditto.Services;

/// <summary>
/// Ensures one running Ditto. The first instance owns a named mutex and listens
/// on a named pipe; later launches (e.g. opening a ditto:// link) forward their
/// argument to the original instance and exit. This mirrors the single-window
/// behavior of the macOS app, where opening a link activates the existing app.
/// </summary>
public sealed class SingleInstance : IDisposable
{
    private const string MutexName = "Ditto.SingleInstance.Mutex";
    private const string PipeName = "Ditto.SingleInstance.Pipe";

    private readonly Mutex _mutex;
    public bool IsFirstInstance { get; }

    /// <summary>Raised on the UI thread when another instance forwards an argument.</summary>
    public event Action<string>? MessageReceived;

    public SingleInstance()
    {
        _mutex = new Mutex(initiallyOwned: true, MutexName, out var createdNew);
        IsFirstInstance = createdNew;
    }

    /// <summary>Send an argument (typically a ditto:// URL) to the running instance.</summary>
    public static void Signal(string argument)
    {
        try
        {
            using var client = new NamedPipeClientStream(".", PipeName, PipeDirection.Out);
            client.Connect(2000);
            using var writer = new StreamWriter(client) { AutoFlush = true };
            writer.WriteLine(argument);
        }
        catch { /* the other instance may be busy; ignore */ }
    }

    /// <summary>Begin listening for forwarded arguments (first instance only).</summary>
    public void StartServer()
    {
        var thread = new Thread(ListenLoop) { IsBackground = true, Name = "Ditto-IPC" };
        thread.Start();
    }

    private void ListenLoop()
    {
        while (true)
        {
            try
            {
                using var server = new NamedPipeServerStream(
                    PipeName, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.None);
                server.WaitForConnection();
                using var reader = new StreamReader(server);
                var line = reader.ReadLine();
                if (!string.IsNullOrWhiteSpace(line)) MessageReceived?.Invoke(line);
            }
            catch
            {
                Thread.Sleep(200);
            }
        }
    }

    public void Dispose()
    {
        try { _mutex.ReleaseMutex(); } catch { }
        _mutex.Dispose();
    }
}
