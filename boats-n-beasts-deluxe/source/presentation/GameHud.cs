using Godot;
using BoatsNBeasts.Core;
using V2 = System.Numerics.Vector2;
namespace BoatsNBeasts;

public partial class Game : Node2D
{
    public partial class Hud : Node2D
    {
        public Game Game = null!; public Font TitleFont = null!, BodyFont = null!;
        readonly List<(Rect2 Bounds, ChartOrder Order)> courses = new();

        internal ChartOrder? CourseAt(Vector2 pointer)
        {
            for (int i = courses.Count - 1; i >= 0; i--)
                if (courses[i].Bounds.HasPoint(pointer)) return courses[i].Order;
            return null;
        }
        void Text(Vector2 p, string text, int size = 22, bool heading = false, Color? color = null) => DrawString(heading ? TitleFont : BodyFont, p, text, HorizontalAlignment.Left, -1, size, color ?? NauticalPalette.Cream);
        void Bar(Vector2 p, Vector2 size, float value, Color color)
        { DrawStyleBox(Game.Box(new Color(NauticalPalette.Navy, .8f), 5), new(p, size)); DrawStyleBox(Game.Box(color, 5), new(p, new Vector2(size.X * Math.Clamp(value, 0, 1), size.Y))); }
        Rect2 EquipmentBounds(int slot, int count)
        {
            var size = GetViewportRect().Size;
            float rowWidth = count * 56 - 8;
            return new(new Vector2((size.X - rowWidth) / 2 + slot * 56, size.Y - 62), new Vector2(48, 48));
        }
        public int EquipmentAt(Vector2 pointer)
        {
            var equipped = Enumerable.Range(0, Voyage.UpgradeNames.Length).Where(i => Game.Run.Rank(i) > 0).ToArray();
            for (int slot = 0; slot < equipped.Length; slot++)
                if (EquipmentBounds(slot, equipped.Length).HasPoint(pointer)) return equipped[slot];
            return -1;
        }
        public override void _Draw()
        {
            courses.Clear();
            if (Game.title) return; var r = Game.Run; var size = GetViewportRect().Size;
            if (Game.chartOpen)
            {
                DrawVoyageChart(r, size);
                return;
            }
            if (Game.hitNotice > 0)
                DrawRect(new Rect2(3, 3, size.X - 6, size.Y - 6), new Color(NauticalPalette.Coral, Game.hitNotice * .77f), false, 6);
            string? openingHint = OpeningHint(r);
            int statusInset = (Game.daily.HasValue ? 27 : 0) + (openingHint == null ? 0 : 34);
            DrawVoyageStatus(r, openingHint, statusInset);
            DrawManeuver(r, size);
            DrawKeeper(r);
            var healthPosition = Game.ocean.ElevatedScreen(r.Position, ActorArt3D.BoatHudHeight) + new Vector2(-24, -12);
            Bar(healthPosition, new(48, 6), r.Health / r.MaxHealth, new Color("ed4b55"));
            foreach (var enemy in r.Enemies.Where(e => e.Health < e.MaxHealth && e.Kind != EnemyKind.Leviathan && !e.GuardAnchor.HasValue))
            {
                var at = Game.ocean.ElevatedScreen(enemy.Position, enemy.Kind == EnemyKind.Serpent ? 1.1f : .55f) + new Vector2(-17, -8);
                Bar(at, new(34, 4), enemy.Health / enemy.MaxHealth, NauticalPalette.Coral);
            }
            if (Game.lootNoticeTime > 0 && r.IsActive)
            {
                float alpha = Math.Min(1, Game.lootNoticeTime / .4f);
                float width = BodyFont.GetStringSize(Game.lootNotice, fontSize: 21).X;
                var at = Game.ocean.Screen(Game.lootNoticePosition) + new Vector2(-width / 2, -35 - (1.2f - Game.lootNoticeTime) * 24);
                Text(at + Vector2.One, Game.lootNotice, 21, true, new Color(NauticalPalette.Navy, alpha));
                Text(at, Game.lootNotice, 21, true, new Color(NauticalPalette.Cream, alpha));
            }
            if (r.IsBoosting || r.Boost < 100)
            {
                var boostAt = Game.ocean.Screen(r.Position) + new Vector2(0, 36);
                DrawArc(boostAt, 16, .15f, Mathf.Pi - .15f, 24, r.BoostExhausted ? new Color(NauticalPalette.Coral, .7f) : new Color(NauticalPalette.Navy, .9f), 5, true);
                DrawArc(boostAt, 16, .15f, .15f + (Mathf.Pi - .3f) * Math.Max(.015f, r.Boost / 100), 24, r.BoostExhausted ? NauticalPalette.Coral : NauticalPalette.Aqua, 3, true);
                if (r.BoostExhausted)
                {
                    DrawStyleBox(Game.Box(new Color(NauticalPalette.Navy, .9f), 5), new(boostAt + new Vector2(-55, 20), new Vector2(110, 23)));
                    Text(boostAt + new Vector2(-46, 36), "Release boost", 13);
                }
            }
            var combo = r.ActiveCombo;
            if (combo != null)
            {
                float width = TitleFont.GetStringSize(combo.Name, fontSize: 15).X;
                var at = new Vector2((size.X - width) / 2, size.Y - 77);
                DrawStyleBox(Game.Box(new Color(NauticalPalette.Navy, .88f), 6),
                    new(at - new Vector2(10, 17), new Vector2(width + 20, 23)));
                Text(at, combo.Name, 15, true, NauticalPalette.Gold);
            }
            var equipped = Enumerable.Range(0, Voyage.UpgradeNames.Length).Where(i => r.Rank(i) > 0).ToArray();
            for (int slot = 0; slot < equipped.Length; slot++)
            {
                int item = equipped[slot];
                var bounds = EquipmentBounds(slot, equipped.Length);
                var p = bounds.Position;
                bool paired = combo != null && (item == (int)combo.First || item == (int)combo.Second);
                Color symbol = paired ? NauticalPalette.Gold : NauticalPalette.Aqua;
                Color? border = paired ? new Color(NauticalPalette.Gold, .48f) : null;
                DrawStyleBox(Game.Box(new Color(NauticalPalette.Navy, .65f), 6, border), bounds);
                DrawSetTransform(p + new Vector2(4, 2));
                UpgradeSymbol.DrawSymbol(this, item, symbol);
                DrawSetTransform(Vector2.Zero);
                DrawCircle(p + new Vector2(42, 40), 10, NauticalPalette.Navy);
                Text(p + new Vector2(38, 45), r.Rank(item).ToString(), 13, true);
                if (bounds.HasPoint(Game.uiPointer))
                {
                    string name = $"{Voyage.UpgradeNames[item]} · Rank {r.Rank(item)}";
                    string detail = Voyage.UpgradeDescriptions[item];
                    string pairing = paired ? $"{combo!.Name} · {combo.Description}" : "";
                    float content = Math.Max(BodyFont.GetStringSize(detail, fontSize: 16).X,
                        BodyFont.GetStringSize(pairing, fontSize: 14).X);
                    float width = Math.Max(content, 220) + 28;
                    float height = paired ? 83 : 63;
                    var at = new Vector2(Math.Clamp(p.X + 24 - width / 2, 12, Math.Max(12, size.X - width - 12)),
                        p.Y - height - 34);
                    DrawStyleBox(Game.Box(new Color(NauticalPalette.Navy, .95f), 8), new(at, new Vector2(width, height)));
                    Text(at + new Vector2(14, 24), name, 17, true);
                    Text(at + new Vector2(14, 47), detail, 16);
                    if (paired) Text(at + new Vector2(14, 69), pairing, 14, color: NauticalPalette.Gold);
                }
            }
            Bar(Vector2.Zero, new(size.X, 8), r.Xp / (float)r.NextXp, NauticalPalette.Aqua);
            DrawCompass(size);
            DrawCourseGuide(r, size, statusInset);
            var boss = r.Enemies.FirstOrDefault(e => e.Kind == EnemyKind.Leviathan && e.Health > 0);
            if (boss != null) DrawCrownclaw(boss, size.X / 2);
            if (Game.toastTime > 0 && r.IsActive)
            {
                float y = boss == null ? 113 : 125;
                float x = (size.X - BodyFont.GetStringSize(Game.toast, fontSize: 20).X) / 2;
                DrawStyleBox(Game.Box(new Color(NauticalPalette.Navy, .9f), 10), new(x - 20, y, size.X - x * 2 + 40, 45));
                Text(new(x, y + 30), Game.toast, 20);
            }
        }

        void DrawCrownclaw(Enemy boss, float center)
        {
            const string name = "Crownclaw";
            float titleWidth = TitleFont.GetStringSize(name, fontSize: 29).X;
            DrawStyleBox(Game.Box(new Color(NauticalPalette.Navy, .92f), 10), new(center - 207, 23, 414, 91));
            Text(new(center - titleWidth / 2, 55), name, 29, true);
            Color phase = boss.Grounded ? NauticalPalette.Aqua : boss.Exposed > 0 ? NauticalPalette.Gold : NauticalPalette.Coral;
            Bar(new(center - 180, 67), new(360, 7), boss.Health / boss.MaxHealth, phase);
            string defense = boss.Grounded ? $"Grounded · exposed for {boss.Exposed:0.0}s"
                : boss.Telegraph > 0 && boss.Charge is { HitsCoast: true } ? "Winding up · lane ends at cover"
                : boss.Telegraph > 0 ? "Winding up · cross the marked lane"
                : boss.Dash > 0 ? "Charging"
                : boss.Exposed > 0 ? $"Shell exposed · {boss.Exposed:0.0}s"
                : "Armored";
            Text(new(center - BodyFont.GetStringSize(defense, fontSize: 16).X / 2, 98), defense, 16, color: phase);
        }

        string? OpeningHint(Voyage run)
        {
            if (Game.daily.HasValue || Game.log.HasLitBeacon || run.BossSpawned) return null;
            if (run.Distance < 75 && Game.course.Destination == null)
                return Game.usingController ? "Left stick · Sail to a gold beacon" : "WASD · Steer   /   Click a beacon";
            if (run.Kills == 0) return "Your crew fires automatically";
            return Game.usingController ? "RB · Boost away from beasts" : "Space · Boost away from beasts";
        }

        void DrawVoyageStatus(Voyage run, string? openingHint, int statusInset)
        {
            var at = new Vector2(24, 24);
            string task = run.BossSlain ? "The sea is calm" : run.BossSpawned ? "Defeat Crownclaw" : "Light the beacons";
            string detail = run.BossSlain ? "Voyage won" : run.BossSpawned ? "Dodge the marked attacks"
                : $"{run.BeaconsLit} / {run.Beacons.Count} lit    ·    Crownclaw in {ClockText(Math.Max(0, SpawnDirector.BossArrivalSeconds - run.CombatTime))}";
            DrawStyleBox(Game.Box(new Color(NauticalPalette.Navy, .91f), 9), new(at, new Vector2(297, 143 + statusInset)));
            DrawLine(at + new Vector2(15, 78), at + new Vector2(282, 78), new Color(NauticalPalette.Gold, .35f), 1, true);
            Text(at + new Vector2(15, 32), task, 26, true);
            Text(at + new Vector2(15, 61), detail, 16, color: NauticalPalette.Gold);
            string kills = run.Kills == 1 ? "1 beast" : $"{run.Kills} beasts";
            Text(at + new Vector2(15, 102), $"{ClockText(run.CombatTime)}  ·  Level {run.Level}  ·  {kills}", 16);
            float hull = run.Health / run.MaxHealth;
            Color hullColor = hull < .35f ? NauticalPalette.Coral : NauticalPalette.Aqua;
            Text(at + new Vector2(15, 127), $"Hull {Math.Ceiling(run.Health):0}/{run.MaxHealth:0}", 14, color: hullColor);
            Bar(at + new Vector2(126, 116), new(153, 9), hull, hullColor);
            if (Game.daily is { } challenge)
            {
                Color dailyColor = challenge.ObjectiveMet(run) ? NauticalPalette.Aqua : NauticalPalette.Gold;
                Text(at + new Vector2(15, 151), $"Daily · {challenge.Progress(run)}", 15, color: dailyColor);
            }
            if (openingHint != null)
            {
                DrawLine(at + new Vector2(15, 141), at + new Vector2(282, 141), new Color(NauticalPalette.Gold, .35f), 1, true);
                Text(at + new Vector2(15, 163), openingHint, 15, color: NauticalPalette.Gold);
            }
            if (run.Chain >= 2 && run.IsActive)
            {
                var chainAt = at + new Vector2(0, 152 + statusInset);
                DrawStyleBox(Game.Box(new Color(NauticalPalette.Navy, .88f), 7), new(chainAt, new Vector2(139, 36)));
                Text(chainAt + new Vector2(12, 24), $"×{run.Chain} chain", 17, true, NauticalPalette.Gold);
                Bar(chainAt + new Vector2(12, 30), new(115, 3), run.ChainTime / run.ChainDuration, NauticalPalette.Gold);
            }
        }

        void DrawManeuver(Voyage run, Vector2 size)
        {
            if (run.BossSlain) return;
            var at = new Vector2(24, size.Y - 86);
            bool ready = run.ManeuverCooldown <= 0;
            Color accent = ready ? NauticalPalette.Gold : NauticalPalette.Aqua;
            DrawStyleBox(Game.Box(new Color(NauticalPalette.Navy, .92f), 9), new(at, new Vector2(225, 64)));
            DrawStyleBox(Game.Box(new Color(accent, .16f), 6, new Color(accent, .65f)), new(at + new Vector2(12, 11), new Vector2(32, 32)));
            Text(at + new Vector2(22, 34), Game.usingController ? "X" : "E", 19, true, accent);
            Text(at + new Vector2(56, 29), run.Spec.Maneuver, 19, true);
            Text(at + new Vector2(56, 47), ready ? "Ready" : $"{Math.Ceiling(run.ManeuverCooldown):0}s", 13, color: accent);
            Bar(at + new Vector2(12, 54), new(201, 3), 1 - run.ManeuverCooldown / run.ManeuverDuration, accent);
        }

        void DrawCourseGuide(Voyage run, Vector2 size, int statusInset)
        {
            if (!run.IsActive || run.BossSpawned) return;
            if (run.DeliveryBeacon is { } delivery)
            {
                var at = new Vector2(24, 224 + statusInset);
                var color = run.TowTension > .72f ? NauticalPalette.Coral : NauticalPalette.Aqua;
                DrawStyleBox(Game.Box(new Color(NauticalPalette.Navy, .91f), 7), new(at, new Vector2(168, 43)));
                Text(at + new Vector2(12, 21), run.TowTension > .72f ? "Towline strained" : "Towline", 15, true, color);
                Bar(at + new Vector2(12, 30), new(144, 4), run.TowTension, color);
                DrawCourseMarker(delivery.Position, delivery.Name, "Deliver salvage", NauticalPalette.Aqua, size);
                return;
            }

            if ((Game.course.Patrol ?? run.TargetBeacon) is { } beacon)
            {
                bool nearby = V2.DistanceSquared(run.Position, beacon.Position) < 370 * 370;
                bool patrol = beacon.Objective == BeaconObjective.Patrol;
                string detail = Game.course.Patrol == beacon ? (beacon.Started && nearby ? "Patrolling" : "Patrol plotted")
                    : nearby || beacon.Keeper != null ? beacon.Order
                    : $"{Math.Round(V2.Distance(run.Position, beacon.Position)):0} m";
                DrawCourseMarker(beacon.Position, beacon.Name, detail, NauticalPalette.Gold, size,
                    progress: beacon.Started ? beacon.Progress : null, patrol: patrol ? beacon : null);
            }
            if (run.SalvageAvailable)
                DrawCourseMarker(run.Salvage.Position, "Wreck salvage", "Sail close to tow", NauticalPalette.Coral,
                    size, allowOffscreen: false);
        }

        void DrawCourseMarker(V2 world, string name, string detail, Color accent, Vector2 size, bool allowOffscreen = true,
            float? progress = null, Beacon? patrol = null)
        {
            var center = size / 2;
            var projected = Game.ocean.Screen(world);
            var at = projected + new Vector2(0, -71);
            Vector2 bearing = Vector2.Zero;
            bool visible = new Rect2(115, 155, size.X - 260, size.Y - 285).HasPoint(at);
            if (!visible)
            {
                if (!allowOffscreen) return;
                Vector2 delta = projected - center;
                var extent = center - new Vector2(128, 130);
                float scale = Math.Min(extent.X / Math.Max(1, Math.Abs(delta.X)), extent.Y / Math.Max(1, Math.Abs(delta.Y)));
                at = center + delta * Math.Min(1, scale);
                bearing = delta.Normalized();
                at -= bearing * 38;
            }

            var bounds = new Rect2(at + new Vector2(-86, -20), new Vector2(172, 48));
            courses.Add((bounds, new(world, patrol)));
            if (patrol != null && bounds.HasPoint(Game.uiPointer) && Game.course.Patrol != patrol)
                detail = "Click to plot patrol";
            DrawStyleBox(Game.Box(new Color(NauticalPalette.Navy, .91f), 7), bounds);
            Text(at + new Vector2(-TitleFont.GetStringSize(name, fontSize: 16).X / 2, -1), name, 16, true, accent);
            Text(at + new Vector2(-BodyFont.GetStringSize(detail, fontSize: 13).X / 2, 18), detail, 13);
            if (progress is { } amount)
                Bar(at + new Vector2(-72, 23), new(144, 3), amount, accent);
            if (bearing != Vector2.Zero)
            {
                var half = bounds.Size / 2;
                float edge = Math.Min(half.X / Math.Max(.001f, Math.Abs(bearing.X)),
                    half.Y / Math.Max(.001f, Math.Abs(bearing.Y)));
                var tail = bounds.GetCenter() + bearing * (edge + 4);
                var wing = bearing.Orthogonal() * 5;
                DrawColoredPolygon([tail + bearing * 11, tail + wing, tail - wing], accent);
            }
        }

        void DrawKeeper(Voyage run)
        {
            var keeper = run.Enemies.FirstOrDefault(enemy => enemy.GuardAnchor.HasValue && enemy.Health > 0 && !enemy.Emerging);
            if (keeper == null || V2.DistanceSquared(keeper.Position, run.Position) > 600 * 600) return;
            var at = Game.ocean.ElevatedScreen(keeper.Position, 1.34f);
            DrawStyleBox(Game.Box(new Color(NauticalPalette.Navy, .9f), 5), new(at + new Vector2(-33, -20), new Vector2(66, 23)));
            Text(at + new Vector2(-23, -4), "Keeper", 14, true, NauticalPalette.Gold);
            Bar(at + new Vector2(-26, 2), new(52, 4), keeper.Health / keeper.MaxHealth, NauticalPalette.Coral);
        }

        void DrawCompass(Vector2 size)
        {
            var r = Game.Run;
            var center = new Vector2(size.X - 100, 140);
            Color paper = new("e1d1a5"), ink = new("526963"), coast = new("a8ad7e");
            DrawCircle(center + new Vector2(0, 3), 82, new Color(NauticalPalette.Navy, .3f));
            DrawCircle(center, 80, paper);
            DrawArc(center, 77, 0, Mathf.Tau, 64, ink, 1.5f, true);
            DrawArc(center, 63, 0, Mathf.Tau, 64, new Color(ink, .22f), 1, true);
            for (int i = 0; i < 8; i++)
            {
                var direction = Vector2.FromAngle(i * Mathf.Tau / 8);
                DrawLine(center + direction * 12, center + direction * 59, new Color(ink, .15f), 1, true);
                DrawLine(center + direction * 71, center + direction * 75, ink, 1, true);
            }
            Text(center + new Vector2(-5, -64), "N", 13, true, ink);
            foreach (var place in r.World.Places)
            {
                if (!r.World.Discovered.ContainsKey(place.Id) || r.World.Depletion.ContainsKey(place.Id)) continue;
                var offset = NauticalPalette.G(place.Position - r.Position) / 17;
                if (offset.Length() > 56) continue;
                var at = center + offset;
                if (place.Kind == PlaceKind.Harbor) ChartAnchor(at, ink);
                else if (place.Kind == PlaceKind.Barrel)
                {
                    var repair = new Color("98634c");
                    DrawLine(at - new Vector2(4, 0), at + new Vector2(4, 0), repair, 2, true);
                    DrawLine(at - new Vector2(0, 4), at + new Vector2(0, 4), repair, 2, true);
                    courses.Add((new(at - Vector2.One * 7, Vector2.One * 14), new(place.Position, Supply: place, Label: "Repair barrel")));
                }
                else if (place.Kind == PlaceKind.Treasure)
                {
                    DrawRect(new(at - new Vector2(3, 3), new(6, 6)), new Color("b38943"));
                    courses.Add((new(at - Vector2.One * 7, Vector2.One * 14), new(place.Position, Supply: place, Label: "Beach cache")));
                }
                else if (place.Kind == PlaceKind.Current) { var d=NauticalPalette.G(OceanWorld.FlowDirection(place)); DrawLine(at-d*5,at+d*5,ink,1.5f); DrawLine(at+d*5,at+d.Orthogonal()*3,ink,1.5f); }
                else
                {
                    float radius = Math.Clamp(place.Radius / 17, 3, 11);
                    var outline = place.Shape is { } shape
                        ? shape.Shore.Select(p => at + NauticalPalette.G(p) / place.Radius * radius).ToArray()
                        : Enumerable.Range(0, 7).Select(i => at + Vector2.FromAngle(i * Mathf.Tau / 7) * radius * (i % 2 == 0 ? 1 : .8f)).ToArray();
                    DrawColoredPolygon(outline, coast);
                    DrawPolyline(outline.Append(outline[0]).ToArray(), ink, 1, true);
                }
            }
            if (!r.BossSpawned)
            {
                foreach (var beacon in r.Beacons)
                {
                    var d = NauticalPalette.G(beacon.Position - r.Position) / 17;
                    var at = center + (d.Length() > 57 ? d.Normalized() * 57 : d);
                    courses.Add((new Rect2(at - Vector2.One * 9, Vector2.One * 18), new(beacon.Position,
                        !beacon.Lit && beacon.Objective == BeaconObjective.Patrol && !r.Salvage.Towing ? beacon : null)));
                    DrawCircle(at, 6, paper);
                    DrawColoredPolygon([at + new Vector2(0, -5), at + new Vector2(5, 0),
                        at + new Vector2(0, 5), at + new Vector2(-5, 0)], beacon.Lit ? new Color("41776b") : new Color("af6629"));
                }
                if (r.SalvageAvailable && !r.Salvage.Towing)
                {
                    var d = NauticalPalette.G(r.Salvage.Position - r.Position) / 17;
                    var at = center + (d.Length() > 57 ? d.Normalized() * 57 : d);
                    courses.Add((new Rect2(at - Vector2.One * 10, Vector2.One * 20), new(r.Salvage.Position, Label: "Wreck salvage")));
                    var flag = new Color("ad4936");
                    DrawCircle(at, 7, paper);
                    DrawLine(at + new Vector2(-3, -6), at + new Vector2(-3, 6), flag, 2, true);
                    DrawColoredPolygon([at + new Vector2(-3, -6), at + new Vector2(6, -3), at + new Vector2(-3, 1)], flag);
                }
            }
            var boss = r.Enemies.FirstOrDefault(e => e.Kind == EnemyKind.Leviathan && e.Health > 0);
            if (boss != null)
            {
                var d = NauticalPalette.G(boss.Position - r.Position) / 17;
                if (d.Length() > 59) d = d.Normalized() * 59;
                DrawCircle(center + d, 4, new Color("b45143"));
            }
            Vector2[] pointer = [new(0, -8), new(-5, 6), new(0, 3), new(5, 6)];
            DrawColoredPolygon(pointer.Select(p => center + p.Rotated(r.Heading)).ToArray(), NauticalPalette.Navy);
            if (r.IsActive)
            {
                var bounds = ChartToggle;
                DrawStyleBox(Game.Box(new Color(NauticalPalette.Navy, bounds.HasPoint(Game.uiPointer) ? .98f : .83f), 5), bounds);
                Text(bounds.Position + new Vector2(13, 19), Game.usingController ? "Y · Chart" : "Tab · Chart", 14, color: NauticalPalette.Cream);
                if (new Rect2(center - Vector2.One * 80, Vector2.One * 160).HasPoint(Game.uiPointer) &&
                    CourseAt(Game.uiPointer)?.Label is { } label)
                    Text(center + new Vector2(-BodyFont.GetStringSize(label, fontSize: 14).X / 2, 138), label, 14, color: NauticalPalette.Cream);
            }
        }
        void ChartAnchor(Vector2 at, Color ink)
        {
            DrawCircle(at + new Vector2(0, -5), 2, ink, false, 1.5f, true);
            DrawLine(at + new Vector2(0, -3), at + new Vector2(0, 6), ink, 1.5f, true);
            DrawLine(at + new Vector2(-3, -1), at + new Vector2(3, -1), ink, 1.5f, true);
            DrawArc(at + new Vector2(0, 1), 5, 0, Mathf.Pi, 12, ink, 1.5f, true);
        }
    }
}
