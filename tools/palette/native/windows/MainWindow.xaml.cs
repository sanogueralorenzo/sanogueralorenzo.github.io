using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using Forms = System.Windows.Forms;
using Microsoft.Web.WebView2.Core;

namespace PaletteHost;

public partial class MainWindow : Window
{
    private const int HotkeyId = 0x50414C54;
    private const uint ModAlt = 0x0001;
    private const uint VkSpace = 0x20;
    private readonly Forms.NotifyIcon tray;
    private readonly DispatcherTimer clipboardTimer;
    private HwndSource? source;
    private Process? nodeService;
    private CancellationTokenSource? nodeCancellation;
    private string lastClipboardText = "";
    private bool webViewReady;
    private bool shuttingDown;

    public MainWindow()
    {
        InitializeComponent();
        tray = new Forms.NotifyIcon { Icon = System.Drawing.SystemIcons.Application, Visible = true, Text = "Palette" };
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Open Palette", null, (_, _) => PresentLauncher());
        menu.Items.Add("Clipboard History", null, (_, _) => OpenClipboardHistory());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Quit", null, (_, _) => RequestQuit());
        tray.ContextMenuStrip = menu;
        tray.DoubleClick += (_, _) => PresentLauncher();

        SourceInitialized += OnSourceInitialized;
        Loaded += OnLoaded;
        Deactivated += (_, _) => HideLauncher();
        Closing += OnClosing;
        PreviewKeyDown += OnPreviewKeyDown;

        clipboardTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(750) };
        clipboardTimer.Tick += (_, _) => CaptureClipboardIfChanged();
        clipboardTimer.Start();
    }

    public void PresentLauncher()
    {
        if (!IsVisible) Show();
        WindowState = WindowState.Normal;
        Activate();
        Focus();
        if (webViewReady) _ = WebView.CoreWebView2.ExecuteScriptAsync("window.__paletteOpen?.()");
    }

    public void DisposeHost()
    {
        shuttingDown = true;
        clipboardTimer.Stop();
        if (source is not null) UnregisterHotKey(source.Handle, HotkeyId);
        nodeCancellation?.Cancel();
        if (nodeService is { HasExited: false }) nodeService.Kill(entireProcessTree: true);
        nodeService?.Dispose();
        tray.Visible = false;
        tray.Dispose();
    }

    private void RequestQuit()
    {
        shuttingDown = true;
        System.Windows.Application.Current.Shutdown();
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        source = (HwndSource)PresentationSource.FromVisual(this)!;
        source.AddHook(WindowProc);
        var shortcut = ConfiguredHotkey();
        if (!RegisterHotKey(source.Handle, HotkeyId, shortcut.modifiers, shortcut.key))
            Debug.WriteLine($"Palette could not register {shortcut.label}: {Marshal.GetLastWin32Error()}");
        const int cornerPreference = 33;
        var rounded = 2;
        _ = DwmSetWindowAttribute(source.Handle, cornerPreference, ref rounded, sizeof(int));
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        try
        {
            await WebView.EnsureCoreWebView2Async();
            WebView.CoreWebView2.WebMessageReceived += OnWebMessage;
            var ui = Path.Combine(AppContext.BaseDirectory, "ui", "index.html");
            if (!File.Exists(ui)) throw new FileNotFoundException("Palette UI is missing from the application bundle", ui);
            WebView.CoreWebView2.Navigate(new Uri(ui).AbsoluteUri);
            webViewReady = true;
        }
        catch (Exception error)
        {
            Debug.WriteLine($"Palette WebView unavailable: {error.Message}");
            tray.ShowBalloonTip(4000, "Palette could not start", error.Message, Forms.ToolTipIcon.Error);
        }
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (shuttingDown) return;
        e.Cancel = true;
        HideLauncher();
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Escape) return;
        e.Handled = true;
        HideLauncher();
    }

    private void HideLauncher()
    {
        if (IsVisible) Hide();
    }

    private void ToggleLauncher()
    {
        if (IsVisible) HideLauncher(); else PresentLauncher();
    }

    private void OpenClipboardHistory()
    {
        PresentLauncher();
        if (webViewReady) _ = WebView.CoreWebView2.ExecuteScriptAsync("window.__paletteOpenClipboard?.()");
    }

    private void OnWebMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        try
        {
            using var document = JsonDocument.Parse(e.WebMessageAsJson);
            if (document.RootElement.TryGetProperty("type", out var typeElement))
            {
                var type = typeElement.GetString();
                if (type == "dismissLauncher") { HideLauncher(); return; }
                if (type == "hostReady") return;
            }
            SendNodeMessage(e.WebMessageAsJson);
        }
        catch (Exception error)
        {
            Debug.WriteLine($"Palette bridge message failed: {error.Message}");
        }
    }

    private void SendNodeMessage(string json)
    {
        StartNodeService();
        nodeService!.StandardInput.WriteLine(json);
        nodeService.StandardInput.Flush();
    }

    private void StartNodeService()
    {
        if (nodeService is { HasExited: false }) return;
        var configured = Environment.GetEnvironmentVariable("PALETTE_NODE_DAEMON");
        var script = configured ?? Path.Combine(AppContext.BaseDirectory, "node", "node-daemon.mjs");
        if (!File.Exists(script)) throw new FileNotFoundException("Palette Node service is missing", script);
        var start = new ProcessStartInfo(ResolveNodeExecutable())
        {
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };
        start.ArgumentList.Add(script);
        start.Environment["PALETTE_DATA_DIR"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Palette");
        start.Environment["PALETTE_CONFIG_DIR"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".palette");
        var indexer = Path.Combine(AppContext.BaseDirectory, "Helpers", "palette-indexer.exe");
        if (File.Exists(indexer)) start.Environment["PALETTE_INDEXER"] = indexer;
        nodeService = Process.Start(start) ?? throw new InvalidOperationException("Could not start Palette Node service");
        nodeService.ErrorDataReceived += (_, eventArgs) => { if (eventArgs.Data is not null) Debug.WriteLine(eventArgs.Data); };
        nodeService.BeginErrorReadLine();
        nodeCancellation = new CancellationTokenSource();
        _ = ReadNodeResponses(nodeService, nodeCancellation.Token);
    }

    private static string ResolveNodeExecutable()
    {
        var candidates = new[]
        {
            Environment.GetEnvironmentVariable("PALETTE_NODE_EXECUTABLE"),
            Path.Combine(AppContext.BaseDirectory, "Helpers", "node.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "nodejs", "node.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "nodejs", "node.exe"),
        };
        foreach (var candidate in candidates)
            if (!string.IsNullOrWhiteSpace(candidate) && File.Exists(candidate)) return candidate;
        throw new FileNotFoundException("Node.js was not found. Set PALETTE_NODE_EXECUTABLE or install Node.js 22.");
    }

    private async Task ReadNodeResponses(Process process, CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested && await process.StandardOutput.ReadLineAsync(cancellationToken) is { } line)
            {
                using var document = JsonDocument.Parse(line);
                if (document.RootElement.TryGetProperty("type", out var type) && type.GetString() == "notification")
                {
                    var notification = document.RootElement.GetProperty("notification");
                    var title = notification.GetProperty("title").GetString() ?? "Palette";
                    var body = notification.TryGetProperty("body", out var bodyElement) ? bodyElement.GetString() ?? "" : "";
                    await Dispatcher.InvokeAsync(() => tray.ShowBalloonTip(3500, title, body, Forms.ToolTipIcon.Info));
                }
                else
                {
                    await Dispatcher.InvokeAsync(() => WebView.CoreWebView2?.PostWebMessageAsJson(line));
                }
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception error) { Debug.WriteLine($"Palette sidecar read failed: {error.Message}"); }
    }

    private void CaptureClipboardIfChanged()
    {
        try
        {
            if (!System.Windows.Clipboard.ContainsText()) return;
            var text = System.Windows.Clipboard.GetText();
            if (string.IsNullOrEmpty(text) || text == lastClipboardText) return;
            lastClipboardText = text;
            var request = JsonSerializer.Serialize(new
            {
                id = $"capture-{Guid.NewGuid()}",
                type = "captureClipboard",
                item = new
                {
                    id = Guid.NewGuid().ToString(),
                    kind = text.Contains("://", StringComparison.Ordinal) ? "url" : "text",
                    content = text,
                    createdAt = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                    pinned = false,
                },
            });
            SendNodeMessage(request);
        }
        catch (ExternalException) { }
        catch (Exception error) { Debug.WriteLine($"Palette clipboard capture failed: {error.Message}"); }
    }

    private static (uint modifiers, uint key, string label) ConfiguredHotkey()
    {
        var value = (Environment.GetEnvironmentVariable("PALETTE_HOTKEY") ?? "alt+space").Replace(" ", "", StringComparison.Ordinal).ToLowerInvariant();
        return value switch
        {
            "ctrl+space" or "control+space" => (0x0002, VkSpace, "Ctrl+Space"),
            "ctrl+shift+space" or "control+shift+space" => (0x0002 | 0x0004, VkSpace, "Ctrl+Shift+Space"),
            _ => (ModAlt, VkSpace, "Alt+Space"),
        };
    }

    private IntPtr WindowProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == 0x0312 && wParam.ToInt32() == HotkeyId) { ToggleLauncher(); handled = true; }
        return IntPtr.Zero;
    }

    [DllImport("user32.dll", SetLastError = true)] private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}
