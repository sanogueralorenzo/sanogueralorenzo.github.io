using Godot;
using UI = CozySora.CozyUITheme;

namespace CozySora;

/// <summary>The application owns navigation and pause; this control owns their presentation.</summary>
public partial class CozyInterface : Control
{
    [Signal] public delegate void ResumeRequestedEventHandler();
    [Signal] public delegate void PauseRequestedEventHandler();
    [Signal] public delegate void DestinationsRequestedEventHandler();
    [Signal] public delegate void SettingsRequestedEventHandler();
    [Signal] public delegate void CharacterRequestedEventHandler(string mode);
    private PanelContainer _panel = null!;
    private ScrollContainer _pauseScroll = null!;
    private ColorRect _shade = null!;
    private Button _resumeButton = null!, _catButton = null!, _gullButton = null!, _menuButton = null!;
    private Label _controls = null!, _heading = null!;
    private ColorRect _dot = null!;
    private readonly List<Button> _buttons = new();

    public override void _Ready()
    {
        SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);
        MouseFilter = MouseFilterEnum.Ignore;
        Theme = UI.MakeTheme();
        _menuButton = MakeButton("Menu", () => EmitSignal(SignalName.PauseRequested));
        _menuButton.SetAnchorsAndOffsetsPreset(LayoutPreset.TopRight);
        _menuButton.OffsetLeft = -118; _menuButton.OffsetRight = -20;
        _menuButton.OffsetTop = 18; _menuButton.OffsetBottom = 66;
        _menuButton.FocusMode = FocusModeEnum.None;
        AddChild(_menuButton);
        _dot = new ColorRect { Color = new Color(1, 1, 1, .55f), MouseFilter = MouseFilterEnum.Ignore };
        _dot.SetAnchorsAndOffsetsPreset(LayoutPreset.Center);
        _dot.OffsetLeft = _dot.OffsetTop = -2; _dot.OffsetRight = _dot.OffsetBottom = 2;
        AddChild(_dot);
        _shade = new ColorRect { Color = new Color(.035f, .11f, .12f, .67f) };
        _shade.SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);
        AddChild(_shade);
        _pauseScroll = new ScrollContainer { HorizontalScrollMode = ScrollContainer.ScrollMode.Disabled, FollowFocus = true };
        _pauseScroll.SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);
        AddChild(_pauseScroll);
        var center = new CenterContainer { SizeFlagsHorizontal = SizeFlags.ExpandFill, SizeFlagsVertical = SizeFlags.ExpandFill };
        _pauseScroll.AddChild(center);
        var margin = new MarginContainer();
        foreach (string side in new[] { "left", "top", "right", "bottom" }) margin.AddThemeConstantOverride("margin_" + side, 20);
        center.AddChild(margin);
        _panel = new PanelContainer();
        var style = UI.Panel(UI.Paper, 22);
        style.ContentMarginLeft = style.ContentMarginRight = style.ContentMarginTop = style.ContentMarginBottom = 28;
        _panel.AddThemeStyleboxOverride("panel", style);
        margin.AddChild(_panel);
        var column = new VBoxContainer();
        column.AddThemeConstantOverride("separation", 14);
        _panel.AddChild(column);
        var brand = new Label { Text = "Cozy Sora", HorizontalAlignment = HorizontalAlignment.Center };
        brand.AddThemeFontOverride("font", UI.TitleFont());
        brand.AddThemeFontSizeOverride("font_size", 32);
        column.AddChild(brand);
        _heading = new Label { HorizontalAlignment = HorizontalAlignment.Center, AutowrapMode = TextServer.AutowrapMode.WordSmart };
        column.AddChild(_heading);
        _resumeButton = MakeButton("Resume exploring", () => EmitSignal(SignalName.ResumeRequested));
        column.AddChild(_resumeButton);
        _buttons.Add(_resumeButton);
        var picker = new HBoxContainer();
        picker.AddThemeConstantOverride("separation", 10);
        column.AddChild(picker);
        _catButton = MakeButton("Cat", () => EmitSignal(SignalName.CharacterRequested, "cat"));
        _gullButton = MakeButton("Seagull", () => EmitSignal(SignalName.CharacterRequested, "gull"));
        foreach (var button in new[] { _catButton, _gullButton })
        {
            button.SizeFlagsHorizontal = SizeFlags.ExpandFill;
            picker.AddChild(button); _buttons.Add(button);
        }
        _controls = new Label { AutowrapMode = TextServer.AutowrapMode.WordSmart, HorizontalAlignment = HorizontalAlignment.Center };
        _controls.AddThemeFontSizeOverride("font_size", 14);
        _controls.AddThemeColorOverride("font_color", UI.Muted);
        column.AddChild(_controls);
        var settings = MakeButton("Settings", () => EmitSignal(SignalName.SettingsRequested));
        UI.Secondary(settings); column.AddChild(settings); _buttons.Add(settings);
        var back = MakeButton("Back to destinations", () => EmitSignal(SignalName.DestinationsRequested));
        UI.Secondary(back); column.AddChild(back); _buttons.Add(back);
        for (int i = 0; i < _buttons.Count; i++)
        {
            _buttons[i].FocusNext = _buttons[i].GetPathTo(_buttons[(i + 1) % _buttons.Count]);
            _buttons[i].FocusPrevious = _buttons[i].GetPathTo(_buttons[(i + _buttons.Count - 1) % _buttons.Count]);
        }
        Resized += ResizeMenu;
        ResizeMenu(); SetPaused(false);
    }

    private static Button MakeButton(string text, Action action)
    {
        var button = new Button { Text = text, CustomMinimumSize = new Vector2(0, 48), FocusMode = FocusModeEnum.All, MouseDefaultCursorShape = CursorShape.PointingHand };
        button.Pressed += action;
        return button;
    }

    public void Configure(string destination) => _heading.Text = destination + " · Paused";
    public void FocusResume() => _resumeButton.GrabFocus();
    public void SetCharacter(string mode, bool touch)
    {
        _catButton.Text = mode == "cat" ? "✓ Cat" : "Cat";
        _gullButton.Text = mode == "gull" ? "✓ Seagull" : "Seagull";
        _controls.Text = touch ? "Left pad to move · drag on the right to look\nJump / Climb · Drop · Boost · Switch"
            : Input.GetConnectedJoypads().Count != 0 ? "Left stick move · right stick look · A jump / climb\nB descend · LB boost · Y switch · Start menu"
            : "WASD move · mouse look · Shift sprint\nSpace jump / climb · C descend · Tab switch · Esc menu";
    }

    public void SetPaused(bool paused)
    {
        _shade.Visible = _pauseScroll.Visible = paused;
        _menuButton.Visible = _dot.Visible = !paused;
        if (paused) Callable.From(_resumeButton.GrabFocus).CallDeferred();
        else if (GetViewport().GuiGetFocusOwner() is { } focus && IsAncestorOf(focus)) focus.ReleaseFocus();
    }

    private void ResizeMenu()
    {
        if (_panel is not null) _panel.CustomMinimumSize = new Vector2(Mathf.Min(490, Mathf.Max(280, Size.X - 40)), _panel.CustomMinimumSize.Y);
    }
}
