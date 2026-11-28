using BoatsNBeasts.Core;
using Godot;
using N = System.Numerics.Vector2;

namespace BoatsNBeasts;

internal partial class FlotillaCommandPilot : Node3D
{
    public FleetCommand Fleet = null!;
    public FleetPilot Run = null!;
    public NativeStage3D Stage = null!;
    Node3D helm = null!, tow = null!;
    readonly Dictionary<(string, int), Node3D> marks = [];
    public override void _Ready()
    {
        Stage = new(); AddChild(Stage); Stage.PaintWater(BluewaterCoast.Water(Fleet.Country.Climate));
        helm = FlotillaCommandArt.Hull(Run.Role, Fleet.Country); Stage.AddChild(helm);
        tow = Run.Role == FleetRole.Tug ? BluewaterArt.Prop(Fleet.Country, "convoy") : FlotillaCommandArt.Patient(Fleet.Country, true); Stage.AddChild(tow);
        foreach (var boom in Run.Obstacles)
        {
            var perch = FlotillaCommandArt.Boom(Fleet.Country, boom); Stage.AddChild(perch);
            perch.Position = NativeStage3D.Point((boom.A + boom.B) * .5f);
            var longAxis = boom.B - boom.A; perch.Rotation = new(0, -MathF.Atan2(longAxis.Y, longAxis.X), 0);
        }
        DrawFleet();
    }
    public Vector2 Screen(N p, float y = .3f) => Stage.Screen(p, y);
    public void DrawFleet()
    {
        var p = Run.Position;
        Stage.Follow(new(p.X + Run.Velocity.X * .12f, p.Y + Run.Velocity.Y * .12f));
        Stage.Advance(Run.Clock);
        helm.Position = NativeStage3D.Point(p, .035f * MathF.Sin(Run.Clock * 2.4f));
        helm.Rotation = new(0, -MathF.Atan2(Run.Bow.X, -Run.Bow.Y), -.025f * MathF.Sin(Run.Clock * 1.7f));
        tow.Visible = Run.Attached;
        if (tow.Visible) { tow.Position = NativeStage3D.Point(Run.Tow); var d = p - Run.Tow; tow.Rotation = new(0, -MathF.Atan2(d.X, -d.Y), 0); }
        var current = Run.Marks().ToArray();
        foreach (var key in marks.Keys.Where(k => !current.Any(m => (m.Kind, m.Index) == k)).ToArray()) { marks[key].QueueFree(); marks.Remove(key); }
        foreach (var m in current)
        {
            var key = (m.Kind, m.Index);
            if (!marks.TryGetValue(key, out var prop))
            {
                prop = m.Index == -1 ? ActorArt3D.Boat(BoatKind.Cutter, new[] { 1, 0, 0, 0, 0, 0 }) :
                    Run.Role == FleetRole.Tender && m.Index >= 0 && m.Index <= 2 ? FlotillaCommandArt.Patient(Fleet.Country, m.Index == 2) :
                    Run.Role == FleetRole.Sloop ? FlotillaCommandArt.Hull(m.Index == 2 ? FleetRole.Tug : FleetRole.Sloop, Fleet.Country) :
                    m.Kind == "port" ? FlotillaCommandArt.Hospital(Fleet.Country) : BluewaterArt.Prop(Fleet.Country, m.Kind);
                Stage.AddChild(prop); marks[key] = prop;
            }
            prop.Position = NativeStage3D.Point(m.Index == -1 ? m.Position + new N(-185, 100) : m.Position);
            if (Run.Role == FleetRole.Sloop && m.Index >= 0) prop.Rotation = new(0, MathF.Sin(Run.Clock * .22f + m.Index) * .8f, 0);
        }
    }
}
