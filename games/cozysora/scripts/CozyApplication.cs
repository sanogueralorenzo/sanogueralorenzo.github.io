using Godot;

namespace CozySora;

/// <summary>Persistent navigation and settings own one disposable gameplay session.</summary>
public partial class CozyApplication : Node
{
    private enum Screen { Selector, Loading, Playing, Paused, Returning, Error }
    private Screen _screen = Screen.Selector;
    private Node3D? _session;
    private CozyMap? _map;
    private CozyPlayer? _player;
    private CozyMapRegistry _registry = null!;
    private CozyLanding _landing = null!;
    private CozyInterface _hud = null!;
    private CozyTouchControls _touch = null!;
    private CanvasLayer _canvas = null!;
    private Control _transition = null!;
    private Label _transitionTitle = null!, _transitionMessage = null!;
    private ProgressBar _progress = null!;
    private Button _errorBack = null!;
    private CozyMapDefinition? _activeDestination;
    private bool _shot;

    public override void _Ready()
    {
        ProcessMode = ProcessModeEnum.Always;
        CozyPlayer.ConfigureInput();
        LoadSettings();
        GetViewport().SizeChanged += ResizeSettings;
        StringName automaticId = "";
        foreach (string arg in OS.GetCmdlineUserArgs())
        {
            if (arg == "--profile") _profile = true;
            if (arg == "--touch") _touchEnabled = true;
            if (arg == "--shot" || arg.StartsWith("--view=", StringComparison.Ordinal) || arg.StartsWith("--capture-dir=", StringComparison.Ordinal)) _shot = true;
            if (arg.StartsWith("--map=", StringComparison.Ordinal)) automaticId = arg[6..];
            if (arg.StartsWith("--capture=", StringComparison.Ordinal)) _capture = arg[10..];
            if (arg.StartsWith("--capture-dir=", StringComparison.Ordinal)) _captureDir = arg[14..];
        }
        if (_profile) RenderingServer.ViewportSetMeasureRenderTime(GetViewport().GetViewportRid(), true);
        _canvas = new CanvasLayer { Layer = 20 };
        AddChild(_canvas);
        _landing = new CozyLanding();
        _canvas.AddChild(_landing);
        _registry = GD.Load<CozyMapRegistry>("res://maps/registry.tres");
        string invalid = _registry.ValidationError();
        if (invalid.Length == 0) _landing.Setup(_registry.Maps);
        _landing.PlayRequested += EnterMap;
        _landing.SettingsRequested += OpenSettings;
        _hud = new CozyInterface();
        _canvas.AddChild(_hud);
        _hud.Hide();
        _hud.PauseRequested += () => _player?.SetMenu(true);
        _hud.ResumeRequested += () => _player?.SetMenu(false);
        _hud.DestinationsRequested += ReturnToSelector;
        _hud.SettingsRequested += OpenSettings;
        _hud.CharacterRequested += mode => _player?.SetMode(mode);
        _touch = new CozyTouchControls();
        _canvas.AddChild(_touch);
        _touch.Hide();
        BuildTransition();
        if (invalid.Length > 0) { ShowError(invalid); return; }
        if (_shot && automaticId.IsEmpty) automaticId = _registry.Maps[0].Id;
        if (!automaticId.IsEmpty) Callable.From(() => EnterMap(automaticId)).CallDeferred();
        else ReportSession("selector");
    }

    private async void EnterMap(StringName id)
    {
        if (_screen != Screen.Selector || _settingsVisible) return;
        var destination = _registry.FindMap(id);
        if (destination == null) { ShowError("That destination is unavailable."); return; }
        _screen = Screen.Loading;
        _activeDestination = destination;
        _landing.SetBusy(true);
        Input.MouseMode = Input.MouseModeEnum.Visible;
        await Cover("On our way to " + destination.Title, "Packing a little summer…");
        _landing.Hide();
        ulong started = Time.GetTicksMsec();
        try
        {
            // Scene roots contain generators; generation yields progress on the main thread.
            var loaded = GD.Load(destination.Scene);
            if (loaded is not PackedScene scene) { ShowError("This destination scene is not a playable scene."); return; }
            var instance = scene.Instantiate();
            if (instance is not CozyMap map)
            {
                instance.Free();
                ShowError("This destination couldn't be prepared.");
                return;
            }
            _session = new Node3D { Name = "GameplaySession", ProcessMode = ProcessModeEnum.Disabled };
            AddChild(_session);
            _session.Hide();
            _map = map;
            _session.AddChild(map);
            map.LoadProgress += LoadingProgress;
            await map.Build();
            _player = new CozyPlayer { ShotMode = _shot, MouseCaptureEnabled = !_touchEnabled };
            _session.AddChild(_player);
            _player.Setup(map, destination.Spawn());
            KeepPauseSurfaces(_session);
            _player.MenuChanged += MenuChanged;
            _player.ModeChanged += CharacterChanged;
            _touch.Player = _player;
            _hud.Configure(destination.Title);
            CharacterChanged(_player.Mode);
            _progress.Value = 100;
            _transitionMessage.Text = "Your summer is ready.";
            _session.Show();
            await ToSignal(GetTree(), SceneTree.SignalName.PhysicsFrame);
            await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
            if (!_player.FixedView) _player.PlaceCamera(.016f, true);
            if (_captureDir.Length > 0)
            {
                DirAccess.MakeDirRecursiveAbsolute(_captureDir);
                _captureViews = new Queue<string>(map.ScenicViews.Keys);
                _capture = System.IO.Path.Combine(_captureDir, "start.png");
            }
            await Uncover();
            _screen = Screen.Playing;
            _session.ProcessMode = ProcessModeEnum.Inherit;
            _hud.Visible = !_shot;
            _hud.SetPaused(false);
            if (!_shot) _player.SetMenu(false);
            _touch.Visible = _touchEnabled && !_shot;
            _captureFrames = 0;
            GD.Print("Cozy Sora MAP_READY id=", id, " build_ms=", Time.GetTicksMsec() - started);
            ReportSession("playing");
        }
        catch (Exception exception)
        {
            GD.PushError(exception.ToString());
            ShowError("This destination couldn't be prepared.");
        }
    }

    private static void KeepPauseSurfaces(Node node)
    {
        if (node is CollisionObject3D collision) collision.DisableMode = CollisionObject3D.DisableModeEnum.MakeStatic;
        foreach (Node child in node.GetChildren()) KeepPauseSurfaces(child);
    }

    private void MenuChanged(bool open)
    {
        if (_screen is not (Screen.Playing or Screen.Paused)) return;
        _screen = open ? Screen.Paused : Screen.Playing;
        _session!.ProcessMode = open ? ProcessModeEnum.Disabled : ProcessModeEnum.Inherit;
        if (_player!.Audio is { } audio) audio.StreamPaused = open;
        _map!.SetPaused(open);
        _hud.SetPaused(open);
        _touch.Visible = _touchEnabled && !open;
        ReportSession(open ? "paused" : "playing");
    }

    private void CharacterChanged(string mode)
    {
        _hud.SetCharacter(mode, _touchEnabled);
        _touch.QueueRedraw();
    }

    private async void ReturnToSelector()
    {
        if (_settingsVisible || _screen is not (Screen.Paused or Screen.Playing or Screen.Error)) return;
        _screen = Screen.Returning;
        if (_session != null)
        {
            _session.ProcessMode = ProcessModeEnum.Disabled;
            if (_player?.Audio is { } audio) audio.StreamPaused = true;
        }
        Input.MouseMode = Input.MouseModeEnum.Visible;
        _touch.Hide();
        _hud.Hide();
        await Cover("Cozy Sora", "Returning to destinations…");
        FreeSession();
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        await ToSignal(GetTree(), SceneTree.SignalName.PhysicsFrame);
        _landing.Show();
        _landing.SetBusy(false);
        await Uncover();
        _screen = Screen.Selector;
        _landing.FocusDefault();
        ReportSession("selector");
    }

    private void FreeSession()
    {
        _touch.Player = null;
        _player = null;
        _map = null;
        _activeDestination = null;
        if (IsInstanceValid(_session)) _session!.QueueFree();
        _session = null;
        RenderingServer.GlobalShaderParameterSet("cat_position", new Vector3(0, -100, 0));
    }

    public override void _UnhandledInput(InputEvent input)
    {
        if (_settingsVisible)
        {
            if (input.IsActionPressed("ui_cancel") || input.IsActionPressed("cozy_pause"))
            {
                CloseSettings();
                GetViewport().SetInputAsHandled();
            }
        }
        else if (_screen == Screen.Paused && (input.IsActionPressed("ui_cancel") || input.IsActionPressed("cozy_pause")))
        {
            _player!.SetMenu(false);
            GetViewport().SetInputAsHandled();
        }
    }

    private void BuildTransition()
    {
        _transition = new Control { Theme = CozyUITheme.MakeTheme() };
        _transition.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        _canvas.AddChild(_transition);
        var shade = new ColorRect { Color = new("edf0df") };
        shade.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        _transition.AddChild(shade);
        var center = new CenterContainer();
        center.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        _transition.AddChild(center);
        var margin = new MarginContainer();
        margin.AddThemeConstantOverride("margin_left", 24);
        margin.AddThemeConstantOverride("margin_right", 24);
        center.AddChild(margin);
        var column = new VBoxContainer();
        column.AddThemeConstantOverride("separation", 20);
        margin.AddChild(column);
        _transitionTitle = new Label { HorizontalAlignment = HorizontalAlignment.Center, AutowrapMode = TextServer.AutowrapMode.WordSmart };
        _transitionTitle.AddThemeFontOverride("font", CozyUITheme.TitleFont());
        _transitionTitle.AddThemeFontSizeOverride("font_size", 30);
        column.AddChild(_transitionTitle);
        _transitionMessage = new Label { HorizontalAlignment = HorizontalAlignment.Center, AutowrapMode = TextServer.AutowrapMode.WordSmart };
        column.AddChild(_transitionMessage);
        _progress = new ProgressBar { ShowPercentage = false, CustomMinimumSize = new(0, 6) };
        _progress.AddThemeStyleboxOverride("background", CozyUITheme.Panel(new("d4dfcd"), 3));
        _progress.AddThemeStyleboxOverride("fill", CozyUITheme.Panel(new("4c7464"), 3));
        column.AddChild(_progress);
        _errorBack = new Button { Text = "Back to destinations", CustomMinimumSize = new(0, 52) };
        _errorBack.Pressed += ReturnToSelector;
        column.AddChild(_errorBack);
        void Resize() => column.CustomMinimumSize = new(Mathf.Min(480, GetViewport().GetVisibleRect().Size.X - 48), column.CustomMinimumSize.Y);
        GetViewport().SizeChanged += Resize;
        Resize();
        _transition.Hide();
    }

    private async Task Cover(string title, string message)
    {
        _transitionTitle.Text = title;
        _transitionMessage.Text = message;
        _progress.Value = 0;
        _progress.Show();
        _errorBack.Hide();
        _transition.Modulate = new(1, 1, 1, 0);
        _transition.Show();
        var fade = CreateTween();
        fade.TweenProperty(_transition, "modulate:a", 1.0, .22);
        await ToSignal(fade, Tween.SignalName.Finished);
    }

    private async Task Uncover()
    {
        var fade = CreateTween();
        fade.TweenProperty(_transition, "modulate:a", 0.0, .32);
        await ToSignal(fade, Tween.SignalName.Finished);
        _transition.Hide();
    }

    private void LoadingProgress(string message, float fraction)
    {
        _transitionMessage.Text = message;
        _progress.Value = fraction * 100;
    }

    private void ShowError(string message)
    {
        _screen = Screen.Error;
        FreeSession();
        _transition.Show();
        _transition.Modulate = Colors.White;
        _transitionTitle.Text = "A little detour";
        _transitionMessage.Text = message;
        _progress.Hide();
        _errorBack.Show();
        Callable.From(_errorBack.GrabFocus).CallDeferred();
    }
}
