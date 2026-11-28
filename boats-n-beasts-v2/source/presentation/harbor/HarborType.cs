using Godot;

namespace BoatsNBeasts;

internal static class HarborType
{
    internal static readonly Color Cream = new("ffedc9"), Brass = new("f6c584"), Teal = new("8cdfce");
    static readonly Font Serif = new SystemFont { FontNames = ["Baskerville", "Georgia", "serif"] };
    internal static Label Text(string value, int size, Color color, bool title = false)
    {
        var label = new Label { Text = value, MouseFilter = Control.MouseFilterEnum.Ignore,
            AutowrapMode = TextServer.AutowrapMode.WordSmart };
        if (title) label.AddThemeFontOverride("font", Serif);
        label.AddThemeFontSizeOverride("font_size", size);
        label.AddThemeColorOverride("font_color", color);
        return label;
    }
    internal static StyleBoxFlat Box(Color color, Color border, int horizontal = 20, int vertical = 12)
    {
        var style = new StyleBoxFlat { BgColor = color, BorderColor = border,
            ContentMarginLeft = horizontal, ContentMarginRight = horizontal,
            ContentMarginTop = vertical, ContentMarginBottom = vertical };
        style.SetBorderWidthAll(1);
        style.SetCornerRadiusAll(5);
        return style;
    }
    internal static Button Button(string text, Action action, bool accent = false)
    {
        var button = new Button { Text = text, MouseDefaultCursorShape = Control.CursorShape.PointingHand };
        button.AddThemeFontSizeOverride("font_size", 20);
        button.AddThemeStyleboxOverride("normal", Box(accent ? new("efc28b") : new("133745"), accent ? Brass : new("678883"), 18, 9));
        button.AddThemeStyleboxOverride("hover", Box(accent ? Cream : new("26515b"), Brass, 18, 9));
        button.AddThemeStyleboxOverride("pressed", Box(Teal, Teal, 18, 9));
        button.AddThemeStyleboxOverride("focus", new StyleBoxFlat { DrawCenter = false, BorderWidthBottom = 3, BorderColor = Teal });
        foreach (var state in new[] { "font_color", "font_hover_color", "font_focus_color" })
            button.AddThemeColorOverride(state, accent ? new("20343b") : Cream);
        button.AddThemeColorOverride("font_pressed_color", new("20343b"));
        button.Pressed += action;
        return button;
    }
}
