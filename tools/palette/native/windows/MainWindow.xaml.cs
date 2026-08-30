using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
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

    public MainWindow()
    {
        InitializeComponent();
        tray = new Forms.NotifyIcon { Icon = System.Drawing.SystemIcons.Application, Visible = true, Text = "Palette" };
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Open Palette", null, (_, _) => ToggleLauncher());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Quit Palette", null, (_, _) => Application.Current.Shutdown());
        tray.ContextMenuStrip = menu;
        tray.DoubleClick += (_, _) => ToggleLauncher();
        Loaded += async (_, _) =>
        {
            source = (HwndSource)PresentationSource.FromVisual(this)!;
            source.AddHook(WindowProc);
            RegisterHotKey(source.Handle, HotkeyId, ModAlt, VkSpace);
            await WebView.EnsureCoreWebView2Async();
            WebView.CoreWebView2.WebMessageReceived += OnWebMessage;
            var ui = Path.Combine(AppContext.BaseDirectory, "ui", "index.html");
            if (File.Exists(ui)) WebView.CoreWebView2.Navigate(new Uri(ui).AbsoluteUri);
        };
    }

    public void DisposeHost()
    {
        if (source is not null) UnregisterHotKey(source.Handle, HotkeyId);
        tray.Visible = false;
        tray.Dispose();
    }

    private void ToggleLauncher()
    {
        if (IsVisible) { Hide(); return; }
        Show();
        Activate();
    }

    private void OnWebMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        // Forward typed bridge messages to the Node sidecar in the host layer.
        Debug.WriteLine(e.WebMessageAsJson);
    }

    private IntPtr WindowProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == 0x0312 && wParam.ToInt32() == HotkeyId) { ToggleLauncher(); handled = true; }
        return IntPtr.Zero;
    }

    [DllImport("user32.dll", SetLastError = true)] private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
