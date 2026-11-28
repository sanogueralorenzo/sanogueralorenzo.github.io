using BoatsNBeasts.Core;
using Godot;
using N2 = System.Numerics.Vector2;

namespace BoatsNBeasts;

internal sealed class DungeonDiorama
{
    readonly Dictionary<int, Node3D> gates = [];
    readonly Node3D[] tokens = new Node3D[3];
    readonly Node3D key, shoe, relic, shuttle;
    static readonly Color Iron = new("4d475b"), Brass = new("e7ab60"), Timber = new("835c48"), Light = new("ffd599"), Paper = new("e6d9ac");
    public DungeonDiorama(Node3D root, LandingYard y)
    {
        var plan = y.Plan; var works = y.Works!;
        Node3D Place(Node3D node, N2 p, float lift = 0)
        { node.Position = new(p.X, YardScenery.Level + lift, p.Y); root.AddChild(node); return node; }
        for (int i = 0; i < plan.Patches.Length; i++)
        {
            var patch = plan.Patches[i]; var b = new ActorGeometry(); Color stone = new(y.Region.Rock), cloth = new(y.Region.Cloth);
            var mouths = plan.Passages.Where(r => r.A == i || r.B == i).Select(r => r.A == i ? r.From : r.To).ToArray();
            for (int j = 0; j < patch.Rim.Length; j++)
            {
                var a = patch.Rim[j]; var end = patch.Rim[(j + 1) % patch.Rim.Length]; float len = N2.Distance(a, end); int stones = Math.Max(1, (int)MathF.Ceiling(len / .62f));
                for (int k = 0; k < stones; k++)
                {
                    var p = N2.Lerp(a, end, (k + .5f) / stones); if (mouths.Any(m => N2.DistanceSquared(m, p) < 1.55f)) continue;
                    var at = p - patch.Center; float h = at.Y > .15f ? .17f : .65f + .11f * (j % 3); var local = new Vector3(at.X, h * .5f, at.Y);
                    b.RoundBox(local, new(.57f, h, .46f), .055f, stone.Lightened(.05f * (k % 3)));
                    b.RoundBox(local + Vector3.Up * (h * .54f), new(.58f, .038f, .47f), .01f, stone.Lerp(Brass, .18f + (k % 4) * .034f));
                    if (h > .2f && k == 0 && j % 3 == 1)
                    {
                        b.Tube([local, local + Vector3.Up * .76f], .065f, Iron, 6);
                        b.Crystal(local + Vector3.Up * .69f, new(.15f, .24f, .15f), Light);
                        b.RoundBox(local + Vector3.Up * .94f, new(.30f, .047f, .26f), .009f, stone);
                    }
                }
            }
            var chalk = new Color(y.Region.Trim).Darkened(.17f);
            for (int j = 0; j < 13; j++)
            {
                float x = -1.78f + j * .29f; float z = -1.70f + (j * 13 % 7) * .06f;
                b.Tube([new(x, .013f, z), new(x + .16f + (j % 4) * .082f, .013f, z - .10f)], .009f, chalk, 5);
            }
            if (i is 4 or 8 or 9)
            {
                float side = patch.Radius.X * .61f;
                foreach (float x in new[] { -side, side })
                {
                    var basePoint = new Vector3(x, 0, -patch.Radius.Y * .58f);
                    b.RoundBox(basePoint + Vector3.Up * .11f, new(.37f, .22f, .38f), .04f, stone);
                    b.Tube([basePoint + Vector3.Up * .18f, basePoint + Vector3.Up * 1.56f], [.14f, .10f], Timber, 8);
                    b.Tube([basePoint + Vector3.Up * .85f, basePoint + new Vector3(x > 0 ? -.50f : .5f, 1.47f, 0)], .065f, Timber, 6);
                }
                var lintel = new Vector3(0, 1.55f, -patch.Radius.Y * .58f);
                b.RoundBox(lintel, new(side * 2 + .48f, .17f, .26f), .034f, Timber);
                for (int strip = 0; strip < 5; strip++)
                {
                    float x = (strip - 2) * .37f;
                    var top = lintel + new Vector3(x, .03f, .14f);
                    b.Polygon([top, top + new Vector3(.28f, 0, 0), top + new Vector3(.28f, -.27f, .07f), top + new Vector3(.07f, -.34f, .08f)], strip % 2 == 0 ? cloth : chalk, Vector3.Back);
                }
                b.Tube([lintel + new Vector3(-.62f, 0, 0), lintel + new Vector3(-.62f, -.36f, 0)], .019f, Iron, 5);
                b.Crystal(lintel + new Vector3(-.62f, -.44f, 0), new(.11f, .16f, .10f), Light);
            }
            if (i is 0 or 2 or 9)
            {
                float x = -patch.Radius.X * .52f, z = -patch.Radius.Y * .38f;
                for (int n = 0; n < 3; n++)
                {
                    var at = new Vector3(x + n * .24f, .14f, z - .10f * (n % 2));
                    b.Tube([at + new Vector3(0, -.10f, .29f), at + new Vector3(.08f, .10f, -.39f)], .108f, Timber, 7);
                    b.Tube([at + new Vector3(.03f, -.04f, .09f), at + new Vector3(.035f, -.025f, .054f)], .12f, Brass, 7);
                }
            }
            if (i is 1 or 5 or 6 or 7)
            {
                foreach (float side in new[] { -.40f, .40f }) b.Tube([new(side, .10f, -.25f), new(side, .69f, -.25f)], .069f, Timber, 7);
                b.Tube([new(-.50f, .62f, -.25f), new(.50f, .62f, -.25f)], .17f, Iron, 10);
                for (int band = -2; band <= 2; band++) b.Tube([new(band * .13f - .021f, .62f, -.25f), new(band * .13f + .02f, .62f, -.25f)], .183f, Brass, 10);
                b.Tube([new(.48f, .64f, -.25f), new(.48f, .94f, .05f), new(.65f, .94f, .05f)], .039f, Brass, 6);
            }
            if (i == 4)
            {
                b.RoundBox(new(0, .37f, 0), new(1.04f, .12f, .65f), .028f, Timber);
                foreach (float x in new[] { -.40f, .40f }) b.RoundBox(new(x, .17f, 0), new(.12f, .36f, .51f), .022f, Iron);
                Place(YardWorkProps.Item("ledger"), patch.Center, .42f);
                for (int peg = 0; peg < 3; peg++) b.RoundBox(new(-.32f + peg * .23f, .47f, -.24f), new(.15f, .085f, .14f), .01f, cloth);
            }
            if (i == 3)
                for (int j = 0; j < 6; j++) b.RoundBox(new(0, .065f * (j + 1), .60f - .21f * j), new(1.37f, .13f * (j + 1), .22f), .024f, j % 2 == 0 ? stone : stone.Lightened(.13f));
            if (i is 0 or 4 or 8)
            {
                var plinth = new Vector3(1.46f, .14f, -1.31f);
                b.RoundBox(plinth, new(1.02f, .27f, .71f), .05f, stone);
                if (y.Region.Climate >= IslandClimate.Saltstep)
                {
                    var model = TideWorkshop.Make(y.Region, i); model.Scale = Vector3.One * .55f;
                    Place(model, patch.Center + new N2(plinth.X, plinth.Z), .29f);
                }
                else switch (y.Region.Climate)
                    {
                        case IslandClimate.Kiln:
                            b.Tube([plinth + new Vector3(-.42f, .24f, 0), plinth + new Vector3(0, .38f, 0), plinth + new Vector3(.55f, .62f, 0)], [.07f, .20f, .09f], Timber, 8);
                            for (int j = 0; j < 3; j++) b.Tube([plinth + new Vector3(-.29f + j * .27f, .33f, -.27f), plinth + new Vector3(-.29f + j * .27f, .17f, 0), plinth + new Vector3(-.29f + j * .27f, .40f, .27f)], .042f, Brass, 6);
                            break;
                        case IslandClimate.Shelf:
                            b.RoundBox(plinth + Vector3.Up * .26f, new(.65f, .50f, .45f), .035f, Iron);
                            b.Tube([plinth + new Vector3(.21f, .46f, 0), plinth + new Vector3(.21f, .85f, 0), plinth + new Vector3(.42f, .85f, 0)], .085f, Brass, 7);
                            foreach (float x in new[] { -.2f, 0, .2f }) b.RoundBox(plinth + new Vector3(x, .27f, .24f), new(.07f, .17f, .027f), .01f, Light);
                            break;
                        case IslandClimate.Delta:
                        case IslandClimate.Reef:
                            for (int j = 0; j < 4; j++)
                            {
                                float x = -.36f + j * .23f; var p = plinth + new Vector3(x, .14f, 0);
                                b.Tube([p, p + new Vector3(0, .49f + .14f * MathF.Sin(j), 0)], .07f, cloth, 8);
                                b.Ring(p + new Vector3(0, .50f + .14f * MathF.Sin(j), 0), .073f, .019f, Brass);
                            }
                            break;
                        case IslandClimate.Orchard:
                            b.Tube([plinth, plinth + new Vector3(0, .53f, 0), plinth + new Vector3(.31f, .76f, .06f)], [.14f, .10f, .028f], Timber, 8);
                            b.Tube([plinth + new Vector3(.04f, .48f, 0), plinth + new Vector3(-.33f, .77f, 0)], .044f, Timber, 7);
                            foreach (float x in new[] { -.29f, .28f }) b.Sphere(plinth + new Vector3(x, .65f, .03f), new(.14f, .17f, .14f), Brass);
                            break;
                        case IslandClimate.Loom:
                            foreach (float x in new[] { -.39f, .39f }) b.RoundBox(plinth + new Vector3(x, .43f, 0), new(.085f, .73f, .10f), .015f, Timber);
                            b.RoundBox(plinth + new Vector3(0, .73f, 0), new(.82f, .08f, .12f), .01f, Brass);
                            for (int j = 0; j < 8; j++) { float x = -.31f + j * .085f; b.Tube([plinth + new Vector3(x, .70f, 0), plinth + new Vector3(x, .22f, .10f)], .024f, j % 2 == 0 ? cloth : Paper, 5); }
                            break;
                        default:
                            b.Tube([plinth, plinth + new Vector3(0, .62f, 0)], .065f, Brass, 7);
                            b.Tube([plinth + new Vector3(-.43f, .63f, 0), plinth + new Vector3(.43f, .63f, 0)], .055f, Brass, 6);
                            foreach (float x in new[] { -.35f, .35f }) { b.Tube([plinth + new Vector3(x, .61f, 0), plinth + new Vector3(x, .32f, 0)], .019f, Timber, 5); b.Sphere(plinth + new Vector3(x, .30f, 0), new(.17f, .044f, .17f), Brass); }
                            break;
                    }
            }
            Place(ShoreSculpture.Bake(b), patch.Center);
        }
        for (int i = 0; i < plan.Passages.Length; i++)
        {
            if (!plan.GateClosed(i)) continue;
            var lane = plan.Passages[i]; var b = new ActorGeometry(); float width = lane.Width;
            foreach (float side in new[] { -width, width }) b.Tube([new(side, .04f, 0), new(side, 1.11f, 0)], .079f, Iron, 7);
            for (int j = 0; j < 7; j++) { float x = Mathf.Lerp(-width, width, j / 6f); b.Tube([new(x, .05f, 0), new(x, .88f, 0)], .035f, Brass, 6); }
            foreach (float h in new[] { .24f, .74f }) b.RoundBox(new(0, h, 0), new(width * 2 + .15f, .081f, .12f), .015f, Iron);
            var node = Place(ShoreSculpture.Bake(b), (lane.From + lane.To) * .5f);
            var axis = lane.To - lane.From; node.Rotation = new(0, MathF.Atan2(axis.X, axis.Y), 0); gates[i] = node;
        }
        relic = Place(YardWorkProps.Item("sealed"), y.Chamber(9)); shuttle = Place(YardWorkProps.Item(works.Mechanism == InnerWork.Loom ? "roll" : "net"), y.Chamber(8));
        Place(YardWorkProps.Item("sealed"), y.Chamber(2)); key = Place(YardWorkProps.Item("keys"), y.Chamber(8));
        string item = works.Mechanism switch { InnerWork.Casting => "mould", InnerWork.Counterpoise => "weight", InnerWork.Floodgate => "net", _ => "flag" };
        for (int i = 0; i < tokens.Length; i++) { tokens[i] = Place(YardWorkProps.Item(item), y.MachinePoint(i)); tokens[i].Scale = Vector3.One * 1.25f; }
        shoe = Place(YardWorkProps.Item("roll"), y.MachinePoint(0)); Sync(y);
    }
    public void Sync(LandingYard y)
    {
        relic.Visible = !y.KeepsakeTaken || y.KeepsakeCarried;
        if (y.KeepsakeCarried) relic.Position = new(y.Player.X, YardScenery.Level + .66f, y.Player.Y + .13f);
        shuttle.Visible = y.ShuttleInPlay && y.ShuttleBeat is >= 1.25f and <= 2.90f;
        if (shuttle.Visible) shuttle.Position = new(y.Shuttle.X, YardScenery.Level + .05f, y.Shuttle.Y);
        foreach (var (index, gate) in gates) gate.Visible = y.Plan.GateClosed(index);
        var works = y.Works!; bool active = y.PassageStage == WorksStage.KeyRoom;
        key.Visible = active && y.Machinery >= 2;
        shoe.Visible = works.Mechanism == InnerWork.Casting && active && y.Machinery < 2;
        if (shoe.Visible) shoe.Position = new(y.Forging.X, YardScenery.Level + .05f, y.Forging.Y);
        for (int i = 0; i < tokens.Length; i++) tokens[i].Visible = works.Mechanism switch { InnerWork.Casting => i == 1, InnerWork.Counterpoise => true, _ => i < 2 && (!active || i >= y.Machinery) };
    }
}
