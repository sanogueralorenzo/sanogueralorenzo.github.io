using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Interop;
using Forms = System.Windows.Forms;
using Microsoft.Web.WebView2.Core;

namespace PaletteHost;

public partial class MainWindow : Window
{
    private const int HotkeyId = 0x50414C54;
    private const uint ModAlt = 0x0001;
    private const uint VkSpace = 0x20;
    private readonly Forms.NotifyIcon tray;
    private HwndSource? source;
    private Process? nodeService;
    private CancellationTokenSource? nodeCancellation;

    public MainWindow()
    {
        InitializeComponent();
        tray = new Forms.NotifyIcon { Icon = System.Drawing.SystemIcons.Application, Visible = true, Text = "Palette" };
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Open Palette", null, (_, _) => ToggleLauncher());
        menu.Items.Add("Clipboard History", null, (_, _) => OpenClipboardHistory());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Quit Palette", null, (_, _) => System.Windows.Application.Current.Shutdown());
        tray.ContextMenuStrip = menu;
        tray.DoubleClick += (_, _) => ToggleLauncher();
        Loaded += async (_, _) =>
        {
            source = (HwndSource)PresentationSource.FromVisual(this)!;
            source.AddHook(WindowProc);
            var shortcut = ConfiguredHotkey();
            RegisterHotKey(source.Handle, HotkeyId, shortcut.modifiers, shortcut.key);
            await WebView.EnsureCoreWebView2Async();
            WebView.CoreWebView2.WebMessageReceived += OnWebMessage;
            var ui = Path.Combine(AppContext.BaseDirectory, "ui", "index.html");
            if (File.Exists(ui)) WebView.CoreWebView2.Navigate(new Uri(ui).AbsoluteUri);
        };
    }

    public void DisposeHost()
    {
        if (source is not null) UnregisterHotKey(source.Handle, HotkeyId);
        nodeCancellation?.Cancel();
        if (nodeService is { HasExited: false }) nodeService.Kill(entireProcessTree: true);
        nodeService?.Dispose();
        tray.Visible = false;
        tray.Dispose();
    }

    private void ToggleLauncher()
    {
        if (IsVisible) { Hide(); return; }
        Show();
        Activate();
    }

    private void OpenClipboardHistory()
    {
        if (!IsVisible) { Show(); Activate(); }
        _ = WebView.CoreWebView2?.ExecuteScriptAsync("window.__paletteOpenClipboard?.()")
            ?? Task.CompletedTask;
    }

    private void OnWebMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        try
        {
            StartNodeService();
            nodeService?.StandardInput.WriteLine(e.WebMessageAsJson);
            nodeService?.StandardInput.Flush();
        }
        catch (Exception error) { Debug.WriteLine($"Palette sidecar unavailable: {error.Message}"); }
    }

    private void StartNodeService()
    {
        if (nodeService is { HasExited: false }) return;
        var configured = Environment.GetEnvironmentVariable("PALETTE_NODE_DAEMON");
        var script = configured ?? Path.Combine(AppContext.BaseDirectory, "node", "node-daemon.mjs");
        if (!File.Exists(script)) script = Path.Combine(AppContext.BaseDirectory, "src", "node-daemon.ts");
        var start = new ProcessStartInfo("node") { UseShellExecute = false, RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
        if (script.EndsWith(".ts", StringComparison.OrdinalIgnoreCase)) start.ArgumentList.Add("--experimental-strip-types");
        start.ArgumentList.Add(script);
        start.Environment["PALETTE_DATA_DIR"] = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Palette");
        nodeService = Process.Start(start) ?? throw new InvalidOperationException("Could not start Palette Node service");
        nodeCancellation = new CancellationTokenSource();
        _ = ReadNodeResponses(nodeService, nodeCancellation.Token);
    }

    private async Task ReadNodeResponses(Process process, CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested && await process.StandardOutput.ReadLineAsync(cancellationToken) is { } line)
                await Dispatcher.InvokeAsync(() => WebView.CoreWebView2?.PostWebMessageAsJson(line));
        }
        catch (OperationCanceledException) { }
        catch (Exception error) { Debug.WriteLine($"Palette sidecar read failed: {error.Message}"); }
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
}
