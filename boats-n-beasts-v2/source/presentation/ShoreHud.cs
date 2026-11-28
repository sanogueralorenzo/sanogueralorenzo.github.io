using Godot;
using BoatsNBeasts.Core;

namespace BoatsNBeasts;

internal partial class ShoreHud : Control
{
    public ShoreExpedition Shore = null!;
    readonly Color deep = new("15363cf0"), paper = new("fff0cc"), mint = new("90e0c7"), gold = new("f3cd83");
    Font font = null!;
    public override void _Ready() { MouseFilter = MouseFilterEnum.Ignore; font = ThemeDB.FallbackFont; }
    public override void _Draw()
    {
        var f = Shore.Fight;
        float w = Size.X, h = Size.Y;
        Card(new(22, 20, 410, 93));
        Text(new(41, 47), "BELLWETHER QUAY", 18, gold);
        Text(new(41, 79), f.Objective, 22, paper);
        DrawLine(new(41, 94), new(406, 94), new Color("487071"), 1);
        if (f.FirstBell >= 0)
        {
            Card(new(22, 118, 265, 39)); Text(new(40, 144), "FITTED    " + ShoreFight.Fittings[f.FirstBell], 18, mint);
        }
        if (f.Phase == QuayPhase.Fork)
        {
            Card(new(22, 118, 465, 67));
            Text(new(39, 144), "West  ·  Quickline shortens hook recovery", 17, paper);
            Text(new(39, 169), "East  ·  Sawtooth edge strengthens each cut", 17, paper);
        }
        if (f.Phase is QuayPhase.Fork or QuayPhase.Belfry)
        {
            for (int i = 0; i < 2; i++)
                if (!f.Rung[i]) Beacon(ShoreFight.Bells[i], f.Phase == QuayPhase.Fork ? ShoreFight.Fittings[i] : ShoreFight.StationNames[i], i);
        }
        else if (f.Phase == QuayPhase.Fishery)
        {
            for (int i = 0; i < 2; i++) if (!f.Floats[i]) Beacon(f.FloatAt(i), "K  ·  Hook net", i);
        }
        else if (f.Phase == QuayPhase.Foundry)
        {
            Beacon(ShoreFight.Mould, "Mould", 1);
            Card(new(22, 162, 405, 38)); Text(new(40, 188), "J  Knock away     K  Pull toward you", 17, paper);
        }
        else if (f.Phase == QuayPhase.Ascent) Beacon(QuayPaths.Belfry, "Upper belfry", 1);
        else if (f.Phase == QuayPhase.Homeward) Beacon(ShoreFight.Dock, "Skiff", 1);
        else if (f.Phase == QuayPhase.Rescue) Beacon(f.Keeper, "Nell Spindle", 1);
        Text(new(43, h - 78), "VITALITY", 15, mint, true);
        Card(new(22, h - 62, 310, 44));
        for (int i = 0; i < f.MaxHealth; i++)
        {
            float x = 38 + i * 19;
            DrawColoredPolygon([new(x, h - 32), new(x + 4, h - 47), new(x + 17, h - 47), new(x + 13, h - 32)], i < f.Health ? mint : new("3e5960"));
        }
        Text(new(205, h - 32), $"{f.Silver}  silver", 19, paper);
        Card(new(w - 647, h - 62, 625, 44));
        Text(new(w - 628, h - 32), $"J  Cut     Space  Dodge     K  {(f.HookWait > 0 ? $"Hook {f.HookWait:0.0}s" : "Crew hook")}     WASD  Move     E  Interact", 18, paper);
        if (f.Phase == QuayPhase.Warden && f.Foes.FirstOrDefault(o => o.Warden) is { } boss)
        {
            Card(new(w - 386, 20, 364, 68)); Text(new(w - 367, 46), "THE BELLWARDEN", 18, gold);
            DrawRect(new(w - 366, 59, 324, 11), new("563e47"));
            DrawRect(new(w - 366, 59, 324f * boss.Health / boss.MaxHealth, 11), new("ed7955"));
        }
        foreach (var foe in f.Foes)
        {
            if (foe.Warden) continue;
            var top = Shore.Stage.Lens.UnprojectPosition(ShoreExpedition.Point(foe.Position, 1.12f));
            DrawRect(new(top.X - 22, top.Y, 44, 5), deep);
            DrawRect(new(top.X - 22, top.Y, 44f * foe.Health / foe.MaxHealth, 5), new("ec9970"));
        }
        var prompt = "";
        if (f.Phase is QuayPhase.Fork or QuayPhase.Belfry && f.NearBell >= 0 && !f.Rung[f.NearBell])
            prompt = f.Phase == QuayPhase.Fork ? $"E   Fit {ShoreFight.Fittings[f.NearBell]}" : "E   Ring shore bell";
        else if (f.Phase == QuayPhase.Ascent && f.AtBelfry) prompt = "E   Fit bell tongue";
        else if (f.Phase == QuayPhase.Rescue && f.BesideKeeper) prompt = "E   Help Nell up";
        else if (f.Phase == QuayPhase.Homeward && f.AtDock) prompt = "E   Board skiff";
        if (prompt != "")
        {
            var loc = Shore.Stage.Lens.UnprojectPosition(ShoreExpedition.Point(f.Player, 1.24f));
            float width = font.GetStringSize(prompt, fontSize: 20).X + 30;
            Card(new(loc.X - width / 2, loc.Y - 26, width, 35)); Text(new(loc.X - width / 2 + 15, loc.Y), prompt, 20, gold);
        }
        if (f.Clock < Shore.VoiceUntil && f.Phase != QuayPhase.Lost)
        {
            string line = "Lio    “" + f.Voice + "”";
            float width = font.GetStringSize(line, fontSize: 19).X + 38;
            Card(new((w - width) / 2, h - 126, width, 40)); Text(new((w - width) / 2 + 19, h - 99), line, 19, paper);
        }
        if (Shore.Paused || f.Phase == QuayPhase.Lost)
        {
            DrawRect(new(0, 0, w, h), new Color("102630bb"));
            string title = Shore.Paused ? "At anchor" : "Lio hauls you aboard";
            Text(new((w - font.GetStringSize(title, fontSize: 38).X) / 2, h / 2 - 63), title, 38, paper);
        }
    }
    void Beacon(System.Numerics.Vector2 position, string name, int index)
    {
        var at = Shore.Stage.Lens.UnprojectPosition(ShoreExpedition.Point(position, 1.18f));
        float width = font.GetStringSize(name, fontSize: 17).X + 25;
        var edge = at.Y < 185 || at.Y > Size.Y - 185 || at.X < width / 2 + 20 || at.X > Size.X - width / 2 - 20;
        var p = at.Clamp(new Vector2(width / 2 + 28, 180), new Vector2(Size.X - width / 2 - 28, Size.Y - 190));
        if (edge && Shore.Fight.Phase == QuayPhase.Fork) p.X = Mathf.Clamp(p.X, index == 0 ? width / 2 + 30 : Size.X * .57f, index == 0 ? Size.X * .42f : Size.X - width / 2 - 30);
        var tip = (at - p).Normalized();
        if (edge && tip.LengthSquared() > .1f)
        {
            var side = new Vector2(-tip.Y, tip.X) * 5;
            var origin = p + tip * (MathF.Abs(tip.X) * width * .48f + 12);
            DrawColoredPolygon([origin + tip * 11, origin + side, origin - side], gold);
        }
        Card(new(p.X - width / 2, p.Y - 13, width, 28)); Text(new(p.X - width / 2 + 12, p.Y + 7), name, 17, gold);
    }
    void Text(Vector2 p, string s, int size, Color c, bool shadow = false)
    {
        if (shadow) DrawStringOutline(font, p, s, HorizontalAlignment.Left, -1, size, 4, deep);
        DrawString(font, p, s, HorizontalAlignment.Left, -1, size, c);
    }
    void Card(Rect2 rect)
    {
        DrawRect(rect, deep);
        DrawLine(rect.Position, rect.Position + new Vector2(rect.Size.X, 0), new("b89e71"), 2);
    }
}
