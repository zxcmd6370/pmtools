using System.IO;

namespace PmToolsGui.Services;

/// <summary>Tiny thread-safe file logger for the Steam-plugin HTTP backend, so we can diagnose the
/// add flow without a console. Writes to %AppData%\PmToolsGui\plugin-backend.log.</summary>
public static class PluginLog
{
    private static readonly object _lock = new();

    public static readonly string FilePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "PmToolsGui", "plugin-backend.log");

    public static void Log(string msg)
    {
        try
        {
            lock (_lock)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
                File.AppendAllText(FilePath, $"[{DateTime.Now:HH:mm:ss.fff}] {msg}{Environment.NewLine}");
            }
        }
        catch { /* logging must never throw */ }
    }
}
