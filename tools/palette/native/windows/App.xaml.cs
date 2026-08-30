using System.Windows;

namespace PaletteHost;

public partial class App : Application
{
    private MainWindow? window;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        window = new MainWindow();
        window.Hide();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        window?.DisposeHost();
        base.OnExit(e);
    }
}
