using System.Windows;

namespace PaletteHost;

public partial class App : System.Windows.Application
{
    private MainWindow? window;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        window = new MainWindow();
        window.PresentLauncher();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        window?.DisposeHost();
        base.OnExit(e);
    }
}
