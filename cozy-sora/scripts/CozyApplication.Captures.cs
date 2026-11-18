using Godot;

namespace CozySora;

public partial class CozyApplication
{
    private string _capture = "", _captureDir = "";
    private Queue<string> _captureViews = new();
    private int _captureFrames;
    private bool _profile, _quitting;
    private double _profileClock;
    private readonly List<double> _frameTimes = new();
    private ulong _lastFrameUsec;

    public override async void _Process(double delta)
    {
        if (IsInstanceValid(_player)) RenderingServer.GlobalShaderParameterSet("cat_position", _player!.GlobalPosition);
        if (_profile)
        {
            ulong now = Time.GetTicksUsec();
            if (_lastFrameUsec > 0) _frameTimes.Add((now - _lastFrameUsec) / 1000.0);
            _lastFrameUsec = now;
            _profileClock += delta;
            if (_profileClock > 5 && _frameTimes.Count > 0)
            {
                _profileClock = 0;
                _frameTimes.Sort();
                var viewport = GetViewport().GetViewportRid();
                GD.Print("Cozy Sora FRAME screen=", _screen.ToString().ToUpperInvariant(), " median_ms=", _frameTimes[_frameTimes.Count / 2],
                    " p95_ms=", _frameTimes[(int)((_frameTimes.Count - 1) * .95)], " max_ms=", _frameTimes[^1],
                    " render_cpu_ms=", RenderingServer.ViewportGetMeasuredRenderTimeCpu(viewport), " render_gpu_ms=", RenderingServer.ViewportGetMeasuredRenderTimeGpu(viewport));
                _frameTimes.Clear();
                GD.Print("Cozy Sora RUNTIME screen=", _screen.ToString().ToUpperInvariant(), " fps=", Engine.GetFramesPerSecond(),
                    " physics_ms=", Performance.GetMonitor(Performance.Monitor.TimePhysicsProcess) * 1000,
                    " viewport=", GetViewport().GetVisibleRect().Size, " audio_db=", AudioServer.GetBusPeakVolumeLeftDb(0, 0));
                if (IsInstanceValid(_player)) GD.Print("Cozy Sora PLAYER mode=", _player!.Mode, " position=", _player.Position,
                    " grounded=", _player.Grounded, " perched=", _player.Perched);
            }
        }
        if (_capture.Length == 0 || _screen is not (Screen.Selector or Screen.Playing) || _quitting) return;
        _captureFrames++;
        if (_captureFrames != 45) return;
        await ToSignal(RenderingServer.Singleton, RenderingServer.SignalName.FramePostDraw);
        using var image = GetViewport().GetTexture().GetImage();
        image.SavePng(_capture);
        GD.Print("Cozy Sora CAPTURE ", _capture);
        if (_profile)
        {
            var rid = GetViewport().GetViewportRid();
            GD.Print("Cozy Sora CAPTURE_COST cpu_ms=", RenderingServer.ViewportGetMeasuredRenderTimeCpu(rid),
                " gpu_ms=", RenderingServer.ViewportGetMeasuredRenderTimeGpu(rid),
                " physics_ms=", Performance.GetMonitor(Performance.Monitor.TimePhysicsProcess) * 1000);
        }
        if (_captureViews.TryDequeue(out string? view))
        {
            _player!.SetView(view);
            _capture = System.IO.Path.Combine(_captureDir, view + ".png");
            _captureFrames = 0;
        }
        else if (OS.GetCmdlineUserArgs().Contains("--quit-after-capture"))
        {
            _quitting = true;
            GetTree().Quit();
        }
        else _capture = "";
    }

    private void ReportSession(string label)
    {
        if (!_profile) return;
        _frameTimes.Clear();
        _profileClock = 0;
        _lastFrameUsec = 0;
        int players = 0, cameras = 0, audio = 0;
        void Count(Node node)
        {
            if (node is CozyPlayer) players++;
            if (node is Camera3D) cameras++;
            if (node is AudioStreamPlayer or AudioStreamPlayer3D) audio++;
            foreach (Node child in node.GetChildren()) Count(child);
        }
        Count(GetTree().Root);
        GD.Print("Cozy Sora SESSION ", label, " active=", IsInstanceValid(_session) ? 1 : 0, " players=", players, " cameras=", cameras,
            " audio=", audio, " orphans=", Performance.GetMonitor(Performance.Monitor.ObjectOrphanNodeCount),
            " fps_cap=", Engine.MaxFps, " vsync=", DisplayServer.WindowGetVsyncMode());
    }
}
