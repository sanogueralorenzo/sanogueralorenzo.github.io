using Godot;

namespace CozySora;

public static class CozyUITheme
{
    public static readonly Color Ink = new("254d4b");
    public static readonly Color Muted = new("61726b");
    public static readonly Color Paper = new("fffdf5");
    public static readonly Color Gold = new("bb8a35");

    public static SystemFont BodyFont() => new() { FontNames = ["Helvetica Neue", "Noto Sans", "DejaVu Sans"] };
    public static SystemFont TitleFont() => new() { FontNames = ["Georgia", "Noto Serif", "DejaVu Serif"] };

    public static StyleBoxFlat Panel(Color color, int radius = 18)
    {
        var style = new StyleBoxFlat { BgColor = color };
        style.SetCornerRadiusAll(radius);
        return style;
    }

    public static StyleBoxFlat ButtonStyle(Color color, Color border = default)
    {
        var style = Panel(color, 12);
        style.ContentMarginLeft = style.ContentMarginRight = 22;
        style.ContentMarginTop = style.ContentMarginBottom = 12;
        style.BorderColor = border;
        style.SetBorderWidthAll(border.A > 0 ? 1 : 0);
        return style;
    }

    public static Theme MakeTheme()
    {
        var theme = new Theme { DefaultFont = BodyFont(), DefaultFontSize = 17 };
        theme.SetColor("font_color", "Label", Ink);
        foreach (string state in new[] { "normal", "hover", "pressed", "hover_pressed" })
            theme.SetColor("font_" + state + "_color", "Button", Paper);
        theme.SetColor("font_focus_color", "Button", Paper);
        theme.SetColor("font_disabled_color", "Button", new Color("9daaa2"));
        theme.SetStylebox("normal", "Button", ButtonStyle(Ink));
        theme.SetStylebox("hover", "Button", ButtonStyle(new Color("346661")));
        theme.SetStylebox("pressed", "Button", ButtonStyle(new Color("193d3a")));
        theme.SetStylebox("disabled", "Button", ButtonStyle(new Color("e1e6db")));
        var focus = Panel(Colors.Transparent, 14);
        focus.BorderColor = Gold;
        focus.SetBorderWidthAll(3);
        focus.ExpandMarginLeft = focus.ExpandMarginRight = focus.ExpandMarginTop = focus.ExpandMarginBottom = 4;
        theme.SetStylebox("focus", "Button", focus);
        theme.SetConstant("outline_size", "Button", 0);
        return theme;
    }

    public static void Secondary(Button button)
    {
        foreach (string name in new[] { "font_color", "font_hover_color", "font_pressed_color", "font_focus_color" })
            button.AddThemeColorOverride(name, Ink);
        button.AddThemeStyleboxOverride("normal", ButtonStyle(new Color("f7f5e9"), new Color("b8c4b4")));
        button.AddThemeStyleboxOverride("hover", ButtonStyle(new Color("e7eddd"), new Color("98af9f")));
        button.AddThemeStyleboxOverride("pressed", ButtonStyle(new Color("d9e3d0"), new Color("809d8f")));
    }
}
