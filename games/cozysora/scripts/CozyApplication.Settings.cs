using Godot;

namespace CozySora;

public partial class CozyApplication
{
    private Control? _settings;
    private VBoxContainer? _settingsColumn;
    private bool _settingsVisible, _muted;
    private bool _touchEnabled = DisplayServer.IsTouchscreenAvailable();
    private float _volume = 1;

    private void LoadSettings()
    {
        using var config = new ConfigFile();
        if (config.Load("user://settings.cfg") == Error.Ok)
        {
            _volume = Mathf.Clamp(config.GetValue("audio", "volume", 1.0).AsSingle(), 0, 1);
            _muted = config.GetValue("audio", "muted", false).AsBool();
            _touchEnabled = config.GetValue("input", "touch", _touchEnabled).AsBool();
        }
        ApplyAudio();
    }

    private void SaveSettings()
    {
        using var config = new ConfigFile();
        config.SetValue("audio", "volume", _volume);
        config.SetValue("audio", "muted", _muted);
        config.SetValue("input", "touch", _touchEnabled);
        config.Save("user://settings.cfg");
        ApplyAudio();
    }

    private void ApplyAudio()
    {
        AudioServer.SetBusVolumeDb(0, Mathf.LinearToDb(Mathf.Max(.001f, _volume)));
        AudioServer.SetBusMute(0, _muted);
    }

    private void OpenSettings()
    {
        if (_settingsVisible || _screen is not (Screen.Selector or Screen.Paused)) return;
        _settingsVisible = true;
        _landing.Hide();
        _hud.Hide();
        _settings = new Control { Theme = CozyUITheme.MakeTheme() };
        _settings.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        _canvas.AddChild(_settings);
        var shade = new ColorRect { Color = _screen == Screen.Selector ? new("e7edde") : new(.03f, .1f, .1f, .65f) };
        shade.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        _settings.AddChild(shade);
        var scroll = new ScrollContainer { HorizontalScrollMode = ScrollContainer.ScrollMode.Disabled, FollowFocus = true };
        scroll.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        _settings.AddChild(scroll);
        var center = new CenterContainer { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill, SizeFlagsVertical = Control.SizeFlags.ExpandFill };
        scroll.AddChild(center);
        var panel = new PanelContainer();
        var style = CozyUITheme.Panel(CozyUITheme.Paper, 20);
        style.ContentMarginLeft = style.ContentMarginTop = style.ContentMarginRight = style.ContentMarginBottom = 24;
        panel.AddThemeStyleboxOverride("panel", style);
        center.AddChild(panel);
        var column = new VBoxContainer();
        _settingsColumn = column;
        ResizeSettings();
        column.AddThemeConstantOverride("separation", 16);
        panel.AddChild(column);
        var heading = new Label { Text = "Make yourself at home", AutowrapMode = TextServer.AutowrapMode.WordSmart };
        heading.AddThemeFontOverride("font", CozyUITheme.TitleFont());
        heading.AddThemeFontSizeOverride("font_size", 25);
        column.AddChild(heading);
        var audioLabel = new Label { Text = "Sound · " + Mathf.RoundToInt(_volume * 100) + "%" };
        column.AddChild(audioLabel);
        var slider = new HSlider { MaxValue = 1, Step = .05, Value = _volume, CustomMinimumSize = new(0, 48) };
        slider.ValueChanged += value =>
        {
            _volume = (float)value;
            audioLabel.Text = "Sound · " + Mathf.RoundToInt((float)value * 100) + "%";
            SaveSettings();
        };
        column.AddChild(slider);
        var mute = new CheckButton { Text = "Mute sound", ButtonPressed = _muted, CustomMinimumSize = new(0, 48) };
        CozyUITheme.Secondary(mute);
        mute.Toggled += value => { _muted = value; SaveSettings(); };
        column.AddChild(mute);
        var touch = new CheckButton { Text = "Touch controls", ButtonPressed = _touchEnabled, CustomMinimumSize = new(0, 48) };
        CozyUITheme.Secondary(touch);
        touch.Toggled += value =>
        {
            _touchEnabled = value;
            if (_player != null) { _player.MouseCaptureEnabled = !value; CharacterChanged(_player.Mode); }
            SaveSettings();
        };
        column.AddChild(touch);
        var back = new Button { Text = "Done", CustomMinimumSize = new(0, 52) };
        back.Pressed += CloseSettings;
        column.AddChild(back);
        Control[] controls = [slider, mute, touch, back];
        for (int i = 0; i < controls.Length; i++)
        {
            var current = controls[i];
            current.FocusNext = current.GetPathTo(controls[(i + 1) % controls.Length]);
            current.FocusPrevious = current.GetPathTo(controls[(i + controls.Length - 1) % controls.Length]);
            current.FocusNeighborBottom = current.FocusNext;
            current.FocusNeighborTop = current.FocusPrevious;
        }
        slider.AddThemeStyleboxOverride("focus", CozyUITheme.MakeTheme().GetStylebox("focus", "Button"));
        back.GrabFocus();
    }

    private void CloseSettings()
    {
        if (!_settingsVisible) return;
        _settingsVisible = false;
        _settings!.QueueFree();
        _settings = null;
        _settingsColumn = null;
        if (_screen == Screen.Selector) { _landing.Show(); _landing.FocusDefault(); }
        else if (_screen == Screen.Paused) { _hud.Show(); _hud.FocusResume(); }
    }

    private void ResizeSettings()
    {
        if (IsInstanceValid(_settingsColumn)) _settingsColumn!.CustomMinimumSize =
            new(Mathf.Min(360, Mathf.Max(220, GetViewport().GetVisibleRect().Size.X - 88)), _settingsColumn.CustomMinimumSize.Y);
    }
}
