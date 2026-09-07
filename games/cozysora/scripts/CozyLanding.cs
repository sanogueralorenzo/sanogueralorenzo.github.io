using Godot;

namespace CozySora;

public partial class CozyLanding : Control
{
    [Signal] public delegate void PlayRequestedEventHandler(StringName mapId);
    [Signal] public delegate void SettingsRequestedEventHandler();

    private ScrollContainer _scroll = null!;
    private MarginContainer _margin = null!;
    private VBoxContainer _column = null!;
    private Label _title = null!, _welcome = null!;
    private Button _settings = null!;
    private Label? _footer;
    private bool _busy;
    private readonly List<Card> _cards = new();
    private readonly List<Button> _buttons = new();
    private sealed record Card(Panel Panel, TextureRect Preview, ShaderMaterial Material,
        VBoxContainer Content, Label Title, Label Description, Label Hint, Control Spacer);

    public override void _Ready()
    {
        SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);
        Theme = CozyUITheme.MakeTheme();
        var background = new ColorRect
        {
            MouseFilter = MouseFilterEnum.Ignore,
            Material = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/landing_background.gdshader") }
        };
        background.SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);
        AddChild(background);
        _scroll = new ScrollContainer { HorizontalScrollMode = ScrollContainer.ScrollMode.Disabled, FollowFocus = true };
        _scroll.SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);
        AddChild(_scroll);
        _margin = new MarginContainer { SizeFlagsHorizontal = SizeFlags.ExpandFill };
        _scroll.AddChild(_margin);
        _column = new VBoxContainer { SizeFlagsHorizontal = SizeFlags.ExpandFill };
        _column.AddThemeConstantOverride("separation", 28);
        _margin.AddChild(_column);
        _column.Resized += Layout;
        var header = new HBoxContainer();
        header.AddThemeConstantOverride("separation", 16);
        _column.AddChild(header);
        var heading = new VBoxContainer { SizeFlagsHorizontal = SizeFlags.ExpandFill };
        heading.AddThemeConstantOverride("separation", 4);
        header.AddChild(heading);
        _title = Label("Cozy Sora", 49);
        _title.AddThemeFontOverride("font", CozyUITheme.TitleFont());
        heading.AddChild(_title);
        _welcome = Label("Slow down. See where summer takes you.", 17, CozyUITheme.Muted);
        _welcome.AutowrapMode = TextServer.AutowrapMode.WordSmart;
        heading.AddChild(_welcome);
        _settings = new Button
        {
            Text = "Settings",
            CustomMinimumSize = new(112, 48),
            SizeFlagsVertical = SizeFlags.ShrinkCenter,
            FocusMode = FocusModeEnum.All
        };
        _settings.Pressed += () => EmitSignal(SignalName.SettingsRequested);
        CozyUITheme.Secondary(_settings);
        header.AddChild(_settings);
        Resized += Layout;
    }

    public void Setup(IEnumerable<CozyMapDefinition> maps)
    {
        foreach (var card in _cards) card.Panel.QueueFree();
        _cards.Clear();
        _buttons.Clear();
        if (IsInstanceValid(_footer)) _footer!.QueueFree();
        foreach (var destination in maps) AddDestination(destination);
        _footer = Label("More destinations coming soon", 14, CozyUITheme.Muted);
        _footer.HorizontalAlignment = HorizontalAlignment.Center;
        _footer.CustomMinimumSize = new(0, 32);
        _column.AddChild(_footer);
        Layout();
        LinkFocus();
        Callable.From(FocusDefault).CallDeferred();
    }

    private void AddDestination(CozyMapDefinition destination)
    {
        var panel = new Panel { MouseFilter = MouseFilterEnum.Pass };
        var style = CozyUITheme.Panel(CozyUITheme.Paper, 20);
        style.ShadowColor = new(.13f, .24f, .20f, .10f);
        style.ShadowSize = 24;
        style.ShadowOffset = new(0, 10);
        style.BorderColor = new("dce3d3");
        style.SetBorderWidthAll(1);
        panel.AddThemeStyleboxOverride("panel", style);
        _column.AddChild(panel);
        var material = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/landing_preview.gdshader") };
        var preview = new TextureRect
        {
            Texture = destination.Preview,
            ExpandMode = TextureRect.ExpandModeEnum.IgnoreSize,
            StretchMode = TextureRect.StretchModeEnum.KeepAspectCovered,
            MouseFilter = MouseFilterEnum.Ignore,
            Material = material
        };
        panel.AddChild(preview);
        var content = new VBoxContainer();
        content.AddThemeConstantOverride("separation", 18);
        panel.AddChild(content);
        content.MinimumSizeChanged += () => Callable.From(Layout).CallDeferred();
        var eyebrow = Label(destination.Subtitle.ToUpperInvariant(), 12, new Color("8d743f"));
        eyebrow.AutowrapMode = TextServer.AutowrapMode.WordSmart;
        content.AddChild(eyebrow);
        var title = Label(destination.Title, 36);
        title.AddThemeFontOverride("font", CozyUITheme.TitleFont());
        title.AutowrapMode = TextServer.AutowrapMode.WordSmart;
        content.AddChild(title);
        var description = Label(destination.Description, 17, CozyUITheme.Muted);
        description.AutowrapMode = TextServer.AutowrapMode.WordSmart;
        description.AddThemeConstantOverride("line_spacing", 5);
        content.AddChild(description);
        var spacer = new Control { SizeFlagsVertical = SizeFlags.ExpandFill };
        content.AddChild(spacer);
        var play = new Button { Text = "Play   →", CustomMinimumSize = new(0, 56), FocusMode = FocusModeEnum.All };
        play.AddThemeFontSizeOverride("font_size", 18);
        play.Pressed += () => { if (!_busy) EmitSignal(SignalName.PlayRequested, destination.Id); };
        content.AddChild(play);
        var hint = Label("On little paws. On open wings.", 13, CozyUITheme.Muted);
        hint.HorizontalAlignment = HorizontalAlignment.Center;
        content.AddChild(hint);
        _buttons.Add(play);
        _cards.Add(new(panel, preview, material, content, title, description, hint, spacer));
    }

    private static Label Label(string text, int fontSize, Color? color = null)
    {
        var label = new Label { Text = text, MouseFilter = MouseFilterEnum.Ignore };
        label.AddThemeFontSizeOverride("font_size", fontSize);
        label.AddThemeColorOverride("font_color", color ?? CozyUITheme.Ink);
        return label;
    }

    private void Layout()
    {
        if (!IsInstanceValid(_column) || !IsInstanceValid(_settings)) return;
        var compact = Size.X < 720;
        var shortLandscape = !compact && Size.Y < 520;
        var shortPortrait = compact && Size.Y < 720;
        var shortView = shortLandscape || shortPortrait;
        int inset = compact ? 24 : (int)Mathf.Clamp((Size.X - 1160) * .5f, 40, 320);
        int top = shortView ? 16 : compact || Size.Y < 600 ? 30 :
            (int)Mathf.Clamp((Size.Y - 590 - Mathf.Max(0, _cards.Count - 1) * 438) * .5f, 44, 260);
        _margin.AddThemeConstantOverride("margin_left", inset);
        _margin.AddThemeConstantOverride("margin_right", inset);
        _margin.AddThemeConstantOverride("margin_top", top);
        _margin.AddThemeConstantOverride("margin_bottom", shortView ? 16 : 28);
        _column.AddThemeConstantOverride("separation", shortView ? 12 : compact ? 26 : 30);
        _title.AddThemeFontSizeOverride("font_size", shortPortrait ? 28 : shortLandscape ? 34 : compact ? 36 : 49);
        _welcome.Visible = !shortView;
        _welcome.AddThemeFontSizeOverride("font_size", compact || shortLandscape ? 14 : 17);
        if (IsInstanceValid(_footer)) _footer!.CustomMinimumSize = new(_footer.CustomMinimumSize.X, shortView ? 24 : 32);
        _settings.CustomMinimumSize = new(compact ? 94 : 112, _settings.CustomMinimumSize.Y);
        _settings.AddThemeFontSizeOverride("font_size", compact ? 14 : 16);
        float width = _column.Size.X > 1 ? _column.Size.X : Size.X - inset * 2;
        foreach (var card in _cards)
        {
            card.Title.AddThemeFontSizeOverride("font_size", shortPortrait ? 26 : shortLandscape ? 28 : compact ? 30 : 36);
            float contentInset = shortView ? 20 : compact ? 24 : 34;
            float pictureWidth = compact ? width : width * (shortLandscape ? .46f : .57f);
            float pictureHeight = shortPortrait ? Mathf.Clamp(width * .5f, 120, 180) : compact ?
                Mathf.Clamp(width * .63f, 195, 300) : shortLandscape ? 250 : 408;
            float contentWidth = compact ? width - 2 * contentInset : width - pictureWidth - 2 * contentInset;
            card.Content.Size = new(Mathf.Max(160, contentWidth), card.Content.Size.Y);
            card.Spacer.Visible = !compact && !shortLandscape;
            card.Hint.Visible = !shortView;
            card.Description.AddThemeFontSizeOverride("font_size", shortView ? 15 : 17);
            card.Content.AddThemeConstantOverride("separation", shortView ? 12 : compact ? 14 : 18);
            float contentHeight = Mathf.Max(card.Content.GetCombinedMinimumSize().Y, shortView ? 0 : compact ? 302 : 340);
            if (!compact) pictureHeight = Mathf.Max(shortLandscape ? 250 : 408, contentHeight + 2 * contentInset);
            card.Panel.CustomMinimumSize = new(card.Panel.CustomMinimumSize.X,
                compact ? pictureHeight + contentHeight + 2 * contentInset : pictureHeight);
            card.Preview.Position = Vector2.Zero;
            card.Preview.Size = new(pictureWidth, pictureHeight);
            card.Material.SetShaderParameter("panel_size", card.Preview.Size);
            card.Material.SetShaderParameter("corners", compact ? new Vector4(20, 20, 0, 0) : new Vector4(20, 0, 0, 20));
            card.Content.Position = compact ? new(contentInset, pictureHeight + contentInset) : new(pictureWidth + contentInset, contentInset);
            card.Content.Size = new(Mathf.Max(160, contentWidth), compact ? contentHeight : pictureHeight - 2 * contentInset);
        }
    }

    private void LinkFocus()
    {
        List<Button> controls = [_settings, .. _buttons];
        for (int i = 0; i < controls.Count; i++)
        {
            var current = controls[i];
            var previous = current.GetPathTo(controls[(i + controls.Count - 1) % controls.Count]);
            var next = current.GetPathTo(controls[(i + 1) % controls.Count]);
            current.FocusNeighborTop = current.FocusNeighborLeft = current.FocusPrevious = previous;
            current.FocusNeighborBottom = current.FocusNeighborRight = current.FocusNext = next;
        }
    }

    public async void FocusDefault()
    {
        if (_busy || _buttons.Count == 0) return;
        _buttons[0].GrabFocus();
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
        if (!_busy && IsVisibleInTree() && GetViewport().GuiGetFocusOwner() == _buttons[0]) _scroll.ScrollVertical = 0;
    }

    public void SetBusy(bool value)
    {
        _busy = value;
        _settings.Disabled = value;
        foreach (var button in _buttons) button.Disabled = value;
    }
}
