using BoatsNBeasts.Core;
using Godot;
using N2 = System.Numerics.Vector2;

namespace BoatsNBeasts;

internal static class YardScenery
{
    public const float Level = ShoreSculpture.Floor;
    static readonly Color Wood = new("8b634d"), Steel = new("484959"), Ivory = new("ebdcba");
    public static Node3D District(LandingYard yard)
    {
        var root = new Node3D(); var region = yard.Region;
        var random = new Random(yard.Plan.Seed);
        void Land(YardPatch patch, bool large)
        {
            var center = patch.Center; float rx = patch.Radius.X, rz = patch.Radius.Y;
            var b = new ActorGeometry();
            Color rock = new(region.Rock), sand = new(region.Ground), trim = new(region.Trim);
            int count = patch.Rim.Length;
            var top = new Vector3[count]; var low = new Vector3[count]; var foot = new Vector3[count];
            for (int i = 0; i < count; i++)
            {
                var edge = patch.Rim[i] - center; float variation = random.NextSingle() * .035f;
                Vector3 P(float scale, float height) => new(edge.X * scale, height, edge.Y * scale);
                top[i] = P(1.038f, Level); low[i] = P(1.06f + variation, .24f + random.NextSingle() * .07f); foot[i] = P(1.13f + variation, -.19f);
            }
            b.Polygon(top, sand, Vector3.Up);
            ShoreBeach.Paint(b, top, rock, sand, yard.Plan.Seed + (int)(center.X * 31 + center.Y * 17));
            for (int i = 0; i < count; i++)
            {
                int k = (i + 1) % count; var outward = (top[i] with { Y = 0 }).Normalized(); var tint = rock.Lightened(random.NextSingle() * .10f);
                b.Polygon([top[i], top[k], low[k], low[i]], tint.Lightened(.10f), outward + Vector3.Up * .55f);
                b.Polygon([low[i], low[k], foot[k], foot[i]], tint, outward);
            }
            var rimTone = sand.Lerp(trim, .30f);
            for (int i = 0; i < count; i++)
            {
                var a = top[i]; var c = top[(i + 1) % count]; var insideA = a * .95f; var insideC = c * .95f;
                float y = Level + .009f;
                if ((i + yard.District) % 3 != 0) b.Polygon([a with { Y = y }, c with { Y = y }, insideC with { Y = y }, insideA with { Y = y }], rimTone, Vector3.Up);
            }
            int n = large ? 90 : 33;
            for (int i = 0; i < n; i++)
            {
                float a = random.NextSingle() * Mathf.Tau, d = MathF.Sqrt(random.NextSingle()) * .92f;
                var p = new Vector3(MathF.Cos(a) * rx * d, Level + .006f, MathF.Sin(a) * rz * d);
                float spread = .04f + .17f * random.NextSingle();
                for (int j = 0; j < 2 + i % 3; j++)
                {
                    var end = p + new Vector3(spread + j * .028f, 0, -spread * .43f);
                    b.Polygon([p, end, p + new Vector3(.015f, 0, .013f)], sand.Darkened(.18f), Vector3.Up);
                    p += new Vector3(.035f, 0, .034f);
                }
            }
            for (int i = 0; i < 8; i++)
            {
                float a = (i + .35f) * Mathf.Tau / 8; var p = new Vector3(MathF.Cos(a) * rx * .96f, Level, MathF.Sin(a) * rz * .96f);
                if (Math.Abs(p.X) < 1.55f || random.NextSingle() < .30f) continue;
                b.Sphere(p, new(.28f, .16f + random.NextSingle() * .22f, .25f), rock.Lightened(.12f), 7, 4);
            }
            if (large && region.Climate == IslandClimate.Kiln)
                for (int i = -1; i <= 1; i += 2)
                {
                    b.Tube([new(i * .48f, Level + .016f, rz * .72f), new(i * .48f, Level + .016f, rz * .12f)], .026f, trim, 5);
                    for (int j = 0; j < 5; j++) b.RoundBox(new(0, Level + .013f, rz * (.14f + j * .14f)), new(1.31f, .026f, .074f), .01f, Wood);
                }
            var terrain = ShoreSculpture.Bake(b); terrain.Position = new(center.X, 0, center.Y); root.AddChild(terrain);
        }
        for (int i = 0; i < yard.Plan.Patches.Length; i++) Land(yard.Plan.Patches[i], i == 0 || i == 3);
        for (int i = 0; i < yard.Plan.Passages.Length; i++)
        {
            var lane = yard.Plan.Passages[i];
            if (i != yard.BrokenBridge) root.AddChild(BuildRoad(lane, lane.From, lane.To, region));
            else
            {
                root.AddChild(BuildRoad(lane, lane.From, N2.Lerp(lane.From, lane.To, .32f), region));
                root.AddChild(BuildRoad(lane, N2.Lerp(lane.From, lane.To, .68f), lane.To, region));
            }
        }
        void Place(Node3D node, N2 p, float height = Level)
        { node.Position = new(p.X, height, p.Y); root.AddChild(node); }
        var arrival = yard.Plan.Patches[0]; var start = arrival.Center + new N2(-.6f, arrival.Radius.Y * .50f);
        var tip = arrival.Center + new N2(-.6f, arrival.Radius.Y + .53f);
        root.AddChild(ShoreSculpture.Causeway(start, tip));
        var boat = ActorArt3D.ShoreSkiff(); Place(boat, tip + new N2(-1.26f, .59f), .03f);
        if (yard.Works != null) return root;
        Place(Workshop(region, yard.District), arrival.Center + new N2(arrival.Radius.X * .57f, -arrival.Radius.Y * .46f));
        if (region.Climate >= IslandClimate.Saltstep)
        {
            var hall = TideHall.Build(region); hall.RotationDegrees = new(0, -17, 0);
            Place(hall, yard.Plan.Summit + new N2(.48f, -yard.Plan.Patches[3].Radius.Y * .75f));
            Place(Workshop(region, yard.District + 1), yard.Plan.Summit + new N2(-1.7f, -2.12f));
        }
        else Place(Workshop(region, yard.District + 1), yard.Plan.Summit + new N2(.5f, -2.91f));
        Place(Workshop(region, yard.District + 2), yard.Plan.Ledger + new N2(.6f, -1.1f));
        Place(Tarp(new(region.Cloth)), yard.Plan.Wayhouse + new N2(.85f, -1.03f));
        Place(YardWorkProps.Item("sealed"), yard.Plan.Pocket);
        Place(YardWorkProps.Item("flag"), yard.Plan.Pocket + new N2(.3f, .27f));
        for (int i = 0; i < 2; i++)
        {
            var p = yard.Plan.Bells[i];
            Place(Station(region, yard.Options[i]), p + new N2(0, -1.57f));
            if (region.Climate == IslandClimate.Kiln)
            {
                Place(FiringRack(i + yard.District), p + new N2(i == 0 ? -1.46f : 1.46f, .72f));
                var unfired = ClayFerry(); unfired.RotationDegrees = new(0, 56, 0);
                Place(unfired, p + new N2(i == 0 ? -1.34f : 1.34f, -.91f), Level + .17f);
            }
            else Place(Workshop(region, i + yard.District + 1), p + new N2(i == 0 ? -1.62f : 1.62f, .80f));
        }
        Place(Tarp(new Color(region.Cloth)), yard.Camp);
        var boarding = yard.Ferry;
        root.AddChild(ShoreSculpture.Causeway(boarding - new N2(.22f, 0), boarding + new N2(.65f, 0)));
        var outbound = ActorArt3D.ShoreSkiff(); outbound.RotationDegrees = new(0, -12, 0);
        Place(outbound, boarding + new N2(1.21f, .31f), .04f);
        if (region.Climate == IslandClimate.Kiln)
            for (int i = 0; i < 3; i++)
            {
                var p = boarding + new N2(1.02f + i * .59f, 1.65f + i * .56f);
                var ferry = ClayFerry(); ferry.Name = "ClayFerry" + i; ferry.RotationDegrees = new(0, 20 + i * 9, 0); Place(ferry, p, .09f);
            }
        return root;
    }
    static MeshInstance3D BuildRoad(YardPassage road, N2 start, N2 finish, LandingRegion region)
    {
        var b = new ActorGeometry(); Vector3 a = new(start.X, Level + .014f, start.Y), z = new(finish.X, Level + .014f, finish.Y);
        var axis = z - a; float length = axis.Length(); var side = axis.Normalized().Cross(Vector3.Up) * road.Width;
        bool timber = road.Road is YardRoad.Planks or YardRoad.Rope;
        Color material = timber ? Wood : new(region.Ground), edge = timber ? Wood.Darkened(.20f) : new(region.Rock);
        int pieces = Math.Max(1, (int)MathF.Ceiling(length / (timber ? .23f : .57f)));
        for (int i = 0; i < pieces; i++)
        {
            var first = a.Lerp(z, (i + .018f) / pieces); var last = a.Lerp(z, (i + .982f) / pieces);
            float s = road.Road == YardRoad.Shoal ? 1 + .14f * MathF.Sin(i * 3.1f) : 1;
            var surface = new[] { first - side * s, first + side * s, last + side * s, last - side * s };
            b.Polygon(surface, material.Lightened(i % 3 * .05f), Vector3.Up);
            for (int j = 0; j < 4; j++)
                b.Polygon([surface[j], surface[(j + 1) % 4], surface[(j + 1) % 4] - Vector3.Up * (timber ? .1f : .37f), surface[j] - Vector3.Up * (timber ? .1f : .37f)], edge, side * (j == 1 ? 1 : -1));
            if (road.Road == YardRoad.Stone && i % 3 == 1) b.RoundBox(first + Vector3.Down * .32f, new(.31f, .77f, .40f), .035f, edge);
        }
        int posts = Math.Max(1, (int)MathF.Ceiling(length / 1.65f));
        if (timber) foreach (int sign in new[] { -1, 1 }) for (int i = 0; i <= posts; i++)
        {
            var p = a.Lerp(z, i / (float)posts) + side * sign;
            b.Tube([p - Vector3.Up * .48f, p + Vector3.Up * .39f], .048f, Wood.Darkened(.20f), 6);
            if (i < posts)
            {
                var q = a.Lerp(z, (i + 1f) / posts) + side * sign;
                b.Tube([p + Vector3.Up * .34f, p.Lerp(q, .5f) + Vector3.Up * .23f, q + Vector3.Up * .34f], .021f, new(region.Trim), 6);
                if (road.Road == YardRoad.Rope) b.Tube([p + Vector3.Up * .31f, q - Vector3.Up * .025f], .013f, new(region.Cloth), 5);
            }
        }
        return ShoreSculpture.Bake(b);
    }
    static MeshInstance3D FiringRack(int batch)
    {
        var b = new ActorGeometry(); Color terracotta = new("b96e50"), ash = new("5b5157");
        foreach (int sign in new[] { -1, 1 }) b.Tube([new(sign * .50f, 0, 0), new(sign * .50f, 1.26f, 0)], .060f, Wood, 7);
        for (int level = 0; level < 2; level++)
        {
            float y = .27f + level * .49f; b.RoundBox(new(0, y, 0), new(1.17f, .073f, .44f), .014f, Wood);
            for (int i = -1; i <= 1; i++)
            {
                var p = new Vector3(i * .32f, y + .13f, .016f);
                if ((batch + level) % 2 == 0)
                {
                    b.Sphere(p, new(.13f, .15f, .13f), terracotta.Lightened(i * .03f + .07f), 8, 5);
                    b.Ring(p + Vector3.Up * .11f, .094f, .026f, new("dc956a"));
                    b.Sphere(p + Vector3.Up * .113f, new(.082f, .012f, .082f), ash);
                }
                else for (int k = 0; k < 3; k++) b.RoundBox(p + new Vector3(0, -.06f + k * .05f, 0), new(.24f, .045f, .26f), .014f, terracotta);
            }
        }
        return ShoreSculpture.Bake(b);
    }
    static MeshInstance3D ClayFerry()
    {
        var b = new ActorGeometry(); Color clay = new("aa6246"), rim = new("d88c5f");
        Vector3[] Row(float y, float half, float end) => [new(0, y, -end), new(-half, y, -end * .59f), new(-half, y, end * .61f), new(-half * .60f, y, end), new(half * .60f, y, end), new(half, y, end * .61f), new(half, y, -end * .59f)];
        b.Loft([Row(-.11f, .11f, .57f), Row(.12f, .25f, .78f), Row(.19f, .25f, .8f)], [clay, rim]);
        b.Polygon(Row(.13f, .22f, .73f), clay.Darkened(.29f), Vector3.Up);
        foreach (float z in new[] { -.39f, 0, .39f }) b.RoundBox(new(0, .19f, z), new(.43f, .032f, .073f), .008f, rim);
        return ShoreSculpture.Bake(b);
    }
    static MeshInstance3D Tarp(Color cloth)
    {
        var b = new ActorGeometry();
        for (int i = -1; i <= 1; i += 2) b.Tube([new(i * .54f, 0, -.29f), new(i * .54f, 1.13f, -.29f)], .046f, Wood, 6);
        for (int i = 0; i < 6; i++)
        {
            float x = -.66f + i * .22f;
            b.Polygon([new(x, 1.21f, -.62f), new(x + .221f, 1.21f, -.62f), new(x + .221f, 1.03f, .13f), new(x, 1.03f, .13f)], i % 2 == 0 ? cloth : Ivory, Vector3.Up);
        }
        b.RoundBox(new(0, .45f, -.21f), new(.99f, .12f, .47f), .023f, Wood);
        b.Sphere(new(.17f, .56f, -.20f), new(.13f, .10f, .14f), new("c7794f"));
        return ShoreSculpture.Bake(b);
    }
    static MeshInstance3D Workshop(LandingRegion region, int variant)
    {
        if (region.Climate >= IslandClimate.Saltstep) return TideWorkshop.Make(region, variant);
        var b = new ActorGeometry(); Color rock = new(region.Rock), trim = new(region.Trim), cloth = new(region.Cloth);
        if (region.Climate == IslandClimate.Kiln)
        {
            b.Sphere(new(0, .48f, 0), new(.90f, .79f, .71f), cloth.Darkened(.12f), 10, 6);
            b.Tube([new(0, .75f, 0), new(0, 1.32f, 0)], [.42f, .27f], rock, 9);
            b.Ring(new(0, 1.31f, 0), .29f, .055f, trim);
            b.Sphere(new(0, .28f, .59f), new(.39f, .35f, .12f), Steel);
            b.Sphere(new(0, .21f, .669f), new(.30f, .21f, .07f), new("f49850"));
            for (int i = -2; i <= 2; i++) b.Tube([new(i * .103f, .038f, .741f), new(i * .103f, .42f - Math.Abs(i) * .056f, .742f)], .019f, Steel);
            for (int i = 0; i < 11; i++) { float a = i * Mathf.Tau / 11; b.RoundBox(new(.82f * MathF.Cos(a), .07f, .65f * MathF.Sin(a)), new(.25f, .14f, .25f), .025f, rock); }
        }
        else if (region.Climate == IslandClimate.Delta || region.Climate == IslandClimate.Loom)
        {
            foreach (int s in new[] { -1, 1 }) b.Tube([new(s * .69f, 0, 0), new(s * .67f, 1.48f, 0)], .076f, Wood);
            b.Tube([new(-.84f, 1.38f, 0), new(.84f, 1.38f, 0)], .075f, trim);
            for (int i = 0; i < 8; i++)
            {
                float x = -.64f + i * .16f;
                b.Polygon([new(x, 1.34f, 0), new(x + .15f, 1.34f, 0), new(x + .14f, .39f, .03f + i % 2 * .08f), new(x, .42f, .03f)], i % 3 == 0 ? cloth : Ivory, Vector3.Back);
            }
        }
        else if (region.Climate == IslandClimate.Orchard)
        {
            b.Tube([new(0, 0, 0), new(-.12f, .69f, 0), new(.1f, 1.48f, 0)], [.20f, .16f, .10f], Wood);
            for (int i = 0; i < 7; i++)
            {
                float a = i * Mathf.Tau / 7; var tip = new Vector3(.57f * MathF.Cos(a), 1.4f + (i % 2) * .21f, .53f * MathF.Sin(a));
                b.Tube([new(0, 1.02f, 0), tip], [.096f, .041f], Wood);
                b.Sphere(tip, new(.45f, .25f, .38f), new("74915e"), 7, 4);
                b.Tube([tip, tip - Vector3.Up * .38f], .016f, Wood); b.Sphere(tip - Vector3.Up * .46f, new(.14f, .20f, .14f), trim);
            }
        }
        else if (region.Climate == IslandClimate.Reef)
        {
            for (int i = 0; i < 8; i++) { float a = i * Mathf.Tau / 8; var p = new Vector3(MathF.Cos(a) * .53f, 0, MathF.Sin(a) * .53f); b.Tube([p, p + new Vector3(.12f, .65f + i % 3 * .20f, 0)], [.15f, .10f], i % 2 == 0 ? cloth : trim, 8); }
        }
        else
        {
            b.RoundBox(new(0, .15f, 0), new(1.50f, .30f, 1.0f), .06f, rock);
            if (region.Climate == IslandClimate.Shelf)
            {
                for (int i = 0; i < 4; i++) { var p = new Vector3((i - 1.5f) * .30f, .18f, 0); b.Tube([p, p + Vector3.Up * (1.04f - .17f * i)], .097f, trim); }
                b.Sphere(new(.09f, .40f, .24f), new(.69f, .41f, .48f), new("dae3dc"));
            }
            else
            {
                foreach (int s in new[] { -1, 1 }) b.Tube([new(s * .51f, .29f, 0), new(s * .51f, 1.29f, 0)], .11f, trim, 8);
                b.RoundBox(new(0, 1.33f, 0), new(1.47f, .19f, .48f), .032f, rock);
                b.Polygon([new(-.79f, 1.42f, .23f), new(0, 1.85f, .23f), new(.79f, 1.42f, .23f)], cloth, Vector3.Back);
                if (region.Climate == IslandClimate.Stars) b.Crystal(new(0, 1.09f, 0), new(.18f, .32f, .18f), trim);
            }
        }
        var art = ShoreSculpture.Bake(b); art.RotationDegrees = new(0, variant % 2 == 0 ? -12 : 16, 0); return art;
    }
    static Node3D Station(LandingRegion region, LandingJob job)
    {
        if (job == LandingJob.Escort) return Tarp(new(region.Cloth));
        if (job is LandingJob.Capstans or LandingJob.Nets) return ShoreSculpture.WindingPost();
        if (job == LandingJob.Mould) return Workshop(region, 0);
        var b = new ActorGeometry();
        for (int i = 0; i < 3; i++)
        {
            var p = new Vector3((i - 1) * .37f, .20f + (i % 2) * .06f, 0);
            b.RoundBox(p, new(.34f, .38f, .45f), .03f, new(region.Cloth));
            b.RoundBox(p + Vector3.Back * .23f, new(.22f, .16f, .02f), .005f, Ivory);
        }
        return ShoreSculpture.Bake(b);
    }
}
