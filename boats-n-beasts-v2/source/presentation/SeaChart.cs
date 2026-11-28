using BoatsNBeasts.Core;
using Godot;
using V2 = System.Numerics.Vector2;

namespace BoatsNBeasts;

internal partial class SeaChart : Control
{
    internal SeaPassage Passage = null!;
    LanternPassage Run => Passage.Run;
    readonly Font text = new SystemFont { FontNames = ["Avenir Next", "Noto Sans"] };
    readonly Font heading = new SystemFont { FontNames = ["Georgia", "Noto Serif"] };
    static readonly Color Ink = new("152c39"), Cream = new("fff0c8"), Brass = new("e5bb78"),
        Blue = new("a4e3cf"), Red = new("ff694e"), Muted = new("b3c6c3");
    Rect2 mainAction, leaveAction;
    Vector2 S(V2 point, float h = 0) => Passage.Stage.Screen(point, h);
    void Words(string value, float x, float y, int size, Color color, bool serif = false, float width = -1, HorizontalAlignment align = HorizontalAlignment.Left)
        => DrawString(serif ? heading : text, new(x, y), value, align, width, size, color);
    void Plate(Rect2 r)
    {
        DrawRect(r, new Color(Ink, .96f));
        DrawLine(r.Position, r.Position + new Vector2(r.Size.X, 0), new Color(Brass, .88f), 2);
    }
    void Bar(Rect2 rect, float fraction, Color color)
    {
        DrawRect(rect, new Color("40525a"));
        DrawRect(new(rect.Position, new(rect.Size.X * Math.Clamp(fraction, 0, 1), rect.Size.Y)), color);
    }

    public override void _Draw()
    {
        if (Passage?.Stage == null) return;
        SurfaceMarks();
        bool boss = Run.Leg == PassageLeg.Keelwidow;
        float w = Size.X, h = Size.Y;
        Plate(new(24, 20, 330, 76));
        Words("THE SILENT WATCH    /    VOYAGE", 42, 44, 14, Brass);
        Words("Lantern Sound", 41, 79, 30, Cream, true);
        if (Run.Battle)
        {
            const float width = 255;
            float left = w - width - 24;
            Plate(new(left, 20, width, 77));
            Words(boss ? "WRECK-HAULER" : "CHANNEL ESCORT", left + 14, 41, 12, Brass);
            Words(boss ? "The Keelwidow" : "Lockerback", left + 14, 66, 24, Cream, true);
            Bar(new(left + 15, 78, width - 30, 5), Run.BeastHealth / (float)Run.BeastMaximum, Red);
        }
        if (Run.Leg == PassageLeg.Salvage)
        {
            Waypoint(Run.RepairBuoy, "Carpenter’s watch", "Rescue two hands · hull patches", Blue);
            Waypoint(Run.PowderBuoy, "Gunner’s watch", "Salvage two kegs · heavy shot", Brass);
        }
        else if (!Run.Battle && !Passage.Ended)
        {
            string detail = Run.Leg switch
            {
                PassageLeg.Work => Run.Rescue ? $"Q to rescue · {Run.Hands}/2" : $"Q to salvage · {Run.Hands}/2",
                PassageLeg.Wreck => "Q to lift the tongue",
                PassageLeg.Homeward => "Deliver the tongue",
                PassageLeg.Delivery => "Come alongside",
                _ => "Find the wreck-hauler"
            };
            if (Run.GuardLive) detail = "Turn side-on · Space hits the gun";
            if (Run.TowLoose) detail = "Q to reattach the painter";
            Waypoint(Run.TaskPosition, Run.TaskName, detail, Blue);
        }
        if (Passage.Paused || Passage.Ended) { Modal(); return; }
        Plate(new(24, h - 88, 272, 63));
        Words($"Hull   {Run.HullHealth} / {Run.HullMaximum}", 41, h - 61, 18, Cream);
        Words($"{Run.Silver} silver", 187, h - 61, 16, Brass, width: 90, align: HorizontalAlignment.Right);
        Bar(new(41, h - 48, 236, 8), Run.HullHealth / (float)Run.HullMaximum, Run.HullHealth < 35 ? Red : Blue);
        if (Run.Repairs > 0)
        {
            var patch = $"E   Patch hull  ×{Run.Repairs}";
            DrawRect(new(24, h - 122, 172, 31), Ink);
            Words(patch, 40, h - 100, 16, Blue);
        }
        float right = w - 403;
        Plate(new(right, h - 88, 379, 63));
        string line = Run.HookCooldown > 0 ? $"Q  Line   {Math.Ceiling(Run.HookCooldown)}s" : "Q  Grapnel";
        string surge = Run.SurgeCooldown > 0 ? $"Shift  Surge   {Math.Ceiling(Run.SurgeCooldown)}s" : "Shift  Surge";
        Words(line, right + 15, h - 61, 17, Run.HookCooldown > 0 ? Muted : Blue);
        Words(surge, right + 185, h - 61, 17, Run.SurgeCooldown > 0 ? Muted : Blue);
        Words("WASD   Helm     ·     Hold Space   Fire", right + 15, h - 36, 16, Cream);
        string status = SailingOrder();
        var tint = Run.Move is HaulerMove.Sounding or HaulerMove.LiningUp or HaulerMove.Throwing && Run.Battle ? Red : Cream;
        float statusWidth = text.GetStringSize(status, fontSize: 17).X + 36;
        float statusX = (w - statusWidth) * .5f;
        Plate(new(statusX, h - 67, statusWidth, 40));
        Words(status, statusX, h - 41, 17, tint, width: statusWidth, align: HorizontalAlignment.Center);
        if (Run.CalloutLeft > 0)
        {
            float length = text.GetStringSize(Run.Callout, fontSize: 18).X + 34;
            Plate(new((w - length) * .5f, h - 144, length, 37));
            Words(Run.Callout, (w - length) * .5f, h - 119, 18, Cream, width: length, align: HorizontalAlignment.Center);
        }
        if (Run.WoundFlash > 0)
            DrawRect(new(Vector2.Zero, Size), new Color(Red, Run.WoundFlash), false, 8);
    }

    string SailingOrder()
    {
        if (Run.TowLoose) return "Loose tow · approach the lifeboat and press Q";
        if (Run.GuardLive) return "Line up a broadside on the spring gun";
        if (!Run.Battle)
            return Run.Leg switch
            {
                PassageLeg.Salvage => "Choose a watch · sail to its flag",
                PassageLeg.Work when Run.Rescue => "Q rescues swimmers · keep tow clear of floats",
                PassageLeg.Work => "Gun cut loose · Q lifts the powder",
                PassageLeg.Delivery => "Bring the watch to the tender",
                PassageLeg.Homeward => "Carry the bell tongue back to the tender",
                PassageLeg.Hunt => "Sail north through the outer lights",
                _ => "Come alongside the broken keel · Q to recover"
            };
        return Run.Move switch
        {
            HaulerMove.Throwing => "Flying wreckage   ·   Leave the marked water",
            HaulerMove.Sounding => "Bell shock   ·   Clear the circle or order Q",
            HaulerMove.LiningUp => "Ram   ·   Turn aside or order Q",
            HaulerMove.Exposed => "Seam exposed   ·   Fire!",
            _ when !Run.InRange => "Close to gun range",
            _ when Run.Leg == PassageLeg.Keelwidow && Run.BeastHealth <= Run.BeastMaximum / 2 => "Plated keel   ·   Q its windup to expose the seam",
            _ when Run.Broadside => "Broadside lined up   ·   Hold Space",
            _ => "Swivel gun   ·   Turn side-on for a broadside"
        };
    }

    void Waypoint(V2 target, string name, string detail, Color color)
    {
        var point = S(target, 1.15f);
        var anchor = new Vector2(Math.Clamp(point.X, 140, Size.X - 140), Math.Clamp(point.Y - 27, 172, Size.Y - 213));
        bool offscreen = Math.Abs(anchor.X - point.X) > 80 || Math.Abs(anchor.Y - point.Y) > 95;
        var offset = target - Run.Hull;
        string compass = Math.Abs(offset.X) > Math.Abs(offset.Y) * .72f ? (offset.X > 0 ? "E" : "W") :
            offset.Y > 0 ? "S" : "N";
        var r = new Rect2(anchor.X - 125, anchor.Y - 36, 250, 51);
        Plate(r);
        string label = offscreen ? $"{name}   {compass} {offset.Length() / 100:0}" : name;
        Words(label, r.Position.X, r.Position.Y + 21, 17, color, true, width: 250, align: HorizontalAlignment.Center);
        Words(detail, r.Position.X, r.Position.Y + 42, 14, Cream, width: 250, align: HorizontalAlignment.Center);
        if (offscreen)
        {
            var dir = (point - anchor).Normalized();
            var tip = new Vector2(anchor.X, dir.Y < 0 ? r.Position.Y : r.End.Y);
            var side = new Vector2(-dir.Y, dir.X) * 6;
            DrawColoredPolygon([tip + dir * 11, tip + side, tip - side], color);
        }
    }

    void SurfaceMarks()
    {
        if (Run.TowAboard && !Run.TowLoose)
        {
            var stern = S(Run.Hull - Run.Bow * 69, .17f);
            var bow = S(Run.Tow + OceanWorld.Unit(Run.Hull - Run.Tow) * 45, .15f);
            DrawLine(stern, bow, Ink, 4, true);
            DrawLine(stern, bow, Brass, 2, true);
        }
        if (Run.GuardLive && Run.GuardFuse > 0)
        {
            var warning = Ring(Run.GuardAim, 115);
            DrawColoredPolygon(warning[..^1], new Color(Red, .22f));
            DrawPolyline(warning, Red, 3, true);
            float progress = 1 - Run.GuardFuse / 1.45f;
            var shot = V2.Lerp(Run.Guard, Run.GuardAim, progress);
            DrawCircle(S(shot, .4f + 2.4f * MathF.Sin(MathF.PI * progress)), 4, Cream);
        }
        var wake = Passage.Wake;
        for (int i = 2; i < wake.Count; i++)
        {
            var aft = OceanWorld.Unit(wake[i] - wake[i - 2]);
            if (aft == V2.Zero) continue;
            var normal = new V2(-aft.Y, aft.X);
            foreach (int side in new[] { -1, 1 })
            {
                float reach = side * (33 + i * 1.8f);
                DrawLine(S(wake[i - 1] + normal * (reach - side * 2)), S(wake[i] + normal * reach), new Color(Cream, .70f - i * .038f), Math.Max(1, 4 - i * .15f), true);
            }
        }
        if (Run.Battle && Run.Move == HaulerMove.LiningUp)
        {
            V2 start = Run.WarningOrigin - Run.Aim * Run.ChargeWidth;
            V2 end = Run.WarningOrigin + Run.Aim * (482 + Run.ChargeWidth);
            V2 normal = new(-Run.Aim.Y, Run.Aim.X);
            V2 offset = normal * Run.ChargeWidth;
            Vector2[] polygon = [S(start - offset), S(start + offset), S(end + offset), S(end - offset)];
            Array.Resize(ref polygon, 5);
            polygon[4] = polygon[0];
            DrawColoredPolygon(polygon[..4], new Color(Red, .16f + Run.Windup * .20f));
            DrawPolyline(polygon, Red, 3, true);
            for (int k = 1; k <= 4; k++)
            {
                var center = start + Run.Aim * (92 * k + 20);
                DrawPolyline([S(center - offset * .42f - Run.Aim * 20), S(center), S(center + offset * .42f - Run.Aim * 20)], new Color(Cream, .82f), 2, true);
            }
        }
        if (Run.Battle && (Run.Move is HaulerMove.Sounding or HaulerMove.Throwing || Run.ImpactFlash > 0))
        {
            var ring = Ring(Run.Blast, Run.WaveRadius);
            DrawColoredPolygon(ring[..^1], new Color(Red, .15f));
            DrawPolyline(ring, Red, 3, true);
            DrawPolyline(Ring(Run.Blast, Run.WaveRadius * (Run.ImpactFlash > 0 ? 1 : .42f + .57f * Run.Windup)), Cream, 2, true);
        }
        if (Run.Battle && Run.Move == HaulerMove.Throwing)
        {
            var shot = V2.Lerp(Run.Beast, Run.Blast, Run.Windup);
            var p = S(shot, .50f + 3.1f * MathF.Sin(Run.Windup * MathF.PI));
            DrawLine(p - Vector2.One * 11, p + Vector2.One * 11, Ink, 11, true);
            DrawLine(p - Vector2.One * 11, p + Vector2.One * 11, Brass, 5, true);
        }
        if (!Run.Battle && !Passage.Ended)
        {
            for (int i = 0; i < Run.Drift.Count; i++)
            {
                var item = Run.Drift[i];
                var point = Run.DriftPosition(item);
                if (Run.Cleared.Contains(i) || V2.DistanceSquared(point, Run.Hull) > 520 * 520) continue;
                if (item.Coin)
                {
                    var gold = S(point, .57f);
                    DrawCircle(gold, 5, Brass);
                    DrawArc(gold, 9, 0, Mathf.Tau, 16, Brass, 1.5f, true);
                }
                else DrawPolyline(Ring(point, 81), new Color(Red, .75f), 2, true);
            }
        }
        if (Run.GunFlash > 0)
        {
            float t = 1 - Run.GunFlash / .26f;
            var travel = V2.Lerp(Run.GunFrom, Run.GunTo, t);
            float air = .36f + MathF.Sin(MathF.PI * t) * .58f;
            DrawLine(S(V2.Lerp(Run.GunFrom, Run.GunTo, Math.Max(0, t - .16f)), air), S(travel, air), Brass, 4, true);
            DrawCircle(S(travel, air), 3.8f, Cream);
            if (t > .72f) DrawArc(S(Run.GunTo, .48f), 6 + t * 14, 0, Mathf.Tau, 12, new Color(Cream, 1 - t), 4, true);
        }
        if (Run.HookFlash > 0)
        {
            var a = S(Run.Hull, .55f); var b = S(Run.HookTo, .6f);
            var mid = (a + b) * .5f + Vector2.Down * 20 * (Run.HookFlash / .58f);
            DrawPolyline([a, mid, b], Ink, 6, true);
            DrawPolyline([a, mid, b], Brass, 3, true);
            DrawArc(b, 8, 0, Mathf.Tau, 12, Cream, 3, true);
        }
    }

    Vector2[] Ring(V2 center, float radius)
    {
        var points = new Vector2[49];
        for (int i = 0; i < points.Length; i++)
        {
            float angle = i * Mathf.Tau / 48;
            points[i] = S(center + new V2(MathF.Cos(angle), MathF.Sin(angle)) * radius);
        }
        return points;
    }

    void Modal()
    {
        DrawRect(new(Vector2.Zero, Size), new Color(Ink, .35f));
        float x = Size.X * .5f - 273, y = Size.Y * .5f - 117;
        Plate(new(x, y, 546, 234));
        bool win = Run.Leg == PassageLeg.Recovered;
        Words(Passage.Paused ? "AT ANCHOR" : "LANTERN SOUND", x + 24, y + 31, 14, Brass);
        Words(Passage.Paused ? "Orders, captain?" : win ? "The bell tongue" : "A towline home", x + 24, y + 78, 37, Cream, true);
        string detail = Passage.Paused ? "The tide will wait." : win ? "Lio lifts the bronze tongue from the wreck’s split keel." : "Vara cuts the towline. The crew reaches the lifeboat.";
        Words(detail, x + 24, y + 116, 19, Cream);
        Words($"{Run.Silver} silver in the ship's purse", x + 24, y + 147, 17, Brass);
        mainAction = new(x + 24, y + 169, Passage.Paused ? 168 : 330, 42);
        DrawRect(mainAction, Blue);
        Words(Passage.Paused ? "Enter   Resume" : "Enter   Return to Last Light Quay", mainAction.Position.X + 14, y + 197, 17, Ink);
        if (Passage.Paused)
        {
            leaveAction = new(x + 205, y + 169, 287, 42);
            DrawRect(leaveAction, new Color("38505b"));
            Words("R   Withdraw with silver", leaveAction.Position.X + 14, y + 197, 17, Cream);
        }
    }

    internal bool ActionAt(Vector2 p)
    {
        if (!Passage.Paused && !Passage.Ended) return false;
        if (mainAction.HasPoint(p))
        {
            if (Passage.Paused) Passage.Resume(); else Passage.Finish();
            return true;
        }
        if (!Passage.Paused || !leaveAction.HasPoint(p)) return false;
        Passage.Finish();
        return true;
    }
}
