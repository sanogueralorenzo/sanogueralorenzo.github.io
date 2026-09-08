using Godot;
namespace BoatsNBeasts;

public enum MenuGlyph { Sail, Key, Chart, Chest, Book, Harbor }

// Native buttons retain text, keyboard focus and activation; ornaments are drawn in code.
public partial class MenuButton : Button
{
    public MenuGlyph Glyph { get; init; }
    public bool Primary { get; init; }

    public override void _Ready()
    {
        CustomMinimumSize = new(0, Primary ? 72 : 64);
        Alignment = HorizontalAlignment.Left;
        MouseDefaultCursorShape = CursorShape.PointingHand;
        AddThemeFontSizeOverride("font_size", 20);
        var ink = Primary ? new Color("103b43") : NauticalPalette.Cream;
        foreach (string state in new[] { "normal", "hover", "pressed", "focus" })
            AddThemeColorOverride("font_" + (state == "normal" ? "color" : state + "_color"), ink);
        AddThemeStyleboxOverride("normal", Surface(Primary ? "64c9b9" : "103342", Primary ? "8cdcca" : "365967"));
        AddThemeStyleboxOverride("hover", Surface(Primary ? "80deca" : "194858", Primary ? "b1efdc" : "63978f"));
        AddThemeStyleboxOverride("pressed", Surface(Primary ? "48ac9f" : "0b2938", Primary ? "79cbb8" : "467b7b", true));
        var focus = new StyleBoxFlat
        {
            BgColor = Colors.Transparent, BorderColor = new("ebd29b"),
            CornerRadiusTopLeft = 12, CornerRadiusTopRight = 12,
            CornerRadiusBottomLeft = 12, CornerRadiusBottomRight = 12,
            ExpandMarginLeft = 3, ExpandMarginRight = 3, ExpandMarginTop = 3, ExpandMarginBottom = 3
        };
        focus.SetBorderWidthAll(2); AddThemeStyleboxOverride("focus", focus);
        MouseEntered += QueueRedraw; MouseExited += QueueRedraw;
        FocusEntered += QueueRedraw; FocusExited += QueueRedraw;
        ButtonDown += QueueRedraw; ButtonUp += QueueRedraw;
    }

    StyleBoxFlat Surface(string fill, string edge, bool pressed = false)
    {
        var style = new StyleBoxFlat
        {
            BgColor = new(fill), BorderColor = new(edge),
            CornerRadiusTopLeft = 10, CornerRadiusTopRight = 10,
            CornerRadiusBottomLeft = 10, CornerRadiusBottomRight = 10,
            ContentMarginLeft = 76, ContentMarginRight = 46,
            ContentMarginTop = pressed ? 18 : 16, ContentMarginBottom = pressed ? 14 : 16,
            ShadowColor = new Color("031722", .3f), ShadowSize = pressed ? 1 : 3,
            ShadowOffset = new(0, pressed ? 1 : 3)
        };
        style.SetBorderWidthAll(1); style.BorderWidthBottom = pressed ? 1 : 3;
        return style;
    }

    public override void _Draw()
    {
        float y = Size.Y / 2 + (IsPressed() ? 2 : 0);
        var ink = Primary ? new Color("174b50") : new Color("a3d4c5");
        DrawCircle(new(36, y), 20, new Color(Primary ? new Color("247568") : new Color("071f2d"), .3f));
        DrawArc(new(36, y), 20, 0, Mathf.Tau, 40, new Color(ink, .25f), 1, true);
        DrawSetTransform(new(21, y - 15), 0, Vector2.One * .75f);
        DrawGlyph(ink);
        DrawSetTransform(Vector2.Zero);
        DrawPolyline([new(Size.X - 30, y - 4), new(Size.X - 26, y), new(Size.X - 30, y + 4)], new Color(ink, .65f), 2, true);
        if (!IsPressed()) DrawLine(new(13, 2), new(Size.X - 13, 2), new Color(Colors.White, Primary ? .18f : .055f), 1, true);
    }

    void DrawGlyph(Color ink)
    {
        void Line(float x, float y, float u, float v) => DrawLine(new(x, y), new(u, v), ink, 2.4f, true);
        void Path(params Vector2[] p) => DrawPolyline(p, ink, 2.4f, true);
        switch (Glyph)
        {
            case MenuGlyph.Sail:
                Line(20, 5, 20, 27); Path(new(17, 8), new(7, 23), new(17, 23));
                Path(new(24, 11), new(33, 23), new(24, 23));
                Path(new(5, 28), new(10, 34), new(29, 34), new(35, 28), new(5, 28)); break;
            case MenuGlyph.Key:
                DrawArc(new(13, 13), 8, 0, Mathf.Tau, 32, ink, 2.4f, true);
                Line(19, 19, 33, 33); Line(27, 27, 32, 22); Line(31, 31, 36, 26); break;
            case MenuGlyph.Chart:
                Path(new(5, 9), new(14, 5), new(26, 10), new(35, 6), new(35, 31), new(26, 35), new(14, 30), new(5, 34), new(5, 9));
                Line(14, 5, 14, 30); Line(26, 10, 26, 35); Line(18, 17, 23, 23); Line(23, 17, 18, 23); break;
            case MenuGlyph.Chest:
                Path(new(6, 19), new(6, 13), new(11, 7), new(29, 7), new(34, 13), new(34, 33), new(6, 33), new(6, 19), new(34, 19));
                Line(12, 8, 12, 32); Line(28, 8, 28, 32); DrawRect(new Rect2(17, 17, 6, 8), ink, false, 2); break;
            case MenuGlyph.Book:
                Path(new(20, 10), new(13, 6), new(4, 6), new(4, 30), new(13, 30), new(20, 34), new(27, 30), new(36, 30), new(36, 6), new(27, 6), new(20, 10), new(20, 34));
                Line(9, 13, 15, 15); Line(25, 15, 31, 13); Line(9, 20, 15, 22); break;
            case MenuGlyph.Harbor:
                Path(new(4, 19), new(20, 6), new(36, 19));
                Path(new(9, 16), new(9, 34), new(31, 34), new(31, 16));
                Path(new(16, 34), new(16, 23), new(24, 23), new(24, 34)); break;
        }
    }
}
