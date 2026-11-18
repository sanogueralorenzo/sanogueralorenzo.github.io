using Godot;

namespace CozySora;

public sealed class HarborNeighborhood
{
    private HarborWorld _map = null!;
    private HarborGeometry _g = null!;
    private readonly RandomNumberGenerator _rng = new();
    private static readonly string[] Walls = ["c5bba0", "bf8e77", "8faca1", "bcb4a8", "acb5c2", "d4bf8b", "b8969b", "90a4b1"];
    private static readonly string[] Trims = ["ece0c6", "dbd9c8", "f0e7d3"];
    public async Task Build(HarborWorld world, HarborGeometry geometry)
    {
        _map = world;
        _g = geometry;
        _rng.Seed = 98213;
        foreach (var plot in Plots())
        {
            House(plot.X, plot.Z, plot.Width, plot.Depth, plot.Yaw, plot.Shop, plot.Index);
            if (plot.Index % 12 == 0)
            {
                _map.EmitSignal(CozyMap.SignalName.LoadProgress, "Opening neighborhood windows…", .34f + plot.Index * .006f);
                await _map.ToSignal(_map.GetTree(), SceneTree.SignalName.ProcessFrame);
            }
        }
        CourtyardInfill();
        GardensAndRoutes();
        StreetFurniture();
        Waterfront();
    }
    public sealed record Plot(float X, float Z, float Width, float Depth, float Yaw, bool Shop, int Index);

    public static List<Plot> Plots()
    {
        var result = new List<Plot>();
        float[] rows = [-87, -49, -14, 28];
        for (int row = 0; row < 4; row++)
            for (int side = 0; side < 2; side++)
                for (int col = 0; col < 4; col++)
                    result.Add(new((side == 0 ? -59 : 28) + col * 14, rows[row], 11.8f, 12, row % 2 == 0 ? Mathf.Pi : 0, row == 0, result.Count));
        foreach (float z in new[] { -68f, 7f })
            foreach (int side in new[] { -1, 1 })
                result.Add(new(side == -1 ? -12 : 28, z, 15, 12, side == -1 ? Mathf.Pi * .5f : -Mathf.Pi * .5f, true, result.Count));
        foreach (float x in new[] { 30f, 44f, 58f, 72f })
            result.Add(new(x, 80, 11.6f, 13, Mathf.Pi, x == 30, result.Count));
        foreach (float z in new[] { 61f, 78f, 95f, 115f })
            result.Add(new(116, z, 12, 12, -Mathf.Pi * .5f, false, result.Count));
        return result;
    }

    private Vector3 Local(Vector3 origin, float yaw, Vector3 p)
    {
        return origin + new Basis(Vector3.Up, yaw) * p;
    }
    private void Box(Vector3 origin, float yaw, Vector3 p, Vector3 size, string color, bool solid = false, string finish = "plaster")
    {
        _g.Box(Local(origin, yaw, p), size, color, solid, yaw, finish);
    }
    private void House(float x, float z, float w, float d, float yaw, bool shop, int index)
    {
        var front = new Vector3(x, 0, z) + new Basis(Vector3.Up, yaw) * new Vector3(0, 0, d * .5f + 2.0f);
        var y = _map.TerrainHeight(front.X, front.Z) + .2f;
        var origin = new Vector3(x, y, z);
        var floors = (shop || index % 4 == 0 ? 3 : 2);
        var h = floors * 3.0f + .5f;
        var wall = Walls[index % Walls.Length];
        var trim = Trims[index % 3];
        // Foundations reach the lowest corner even when the front faces uphill.
        var foundation = 2.4f;
        foreach (var dx in new[] { -w * .5f, w * .5f })
        {
            foreach (var dz in new[] { -d * .5f, d * .5f })
            {
                var corner = Local(origin, yaw, new Vector3(dx, 0, dz));
                foundation = Mathf.Max(foundation, y - _map.HeightAt(corner.X, corner.Z) + .2f);
            }
        }
        Box(origin, yaw, new Vector3(0, (h - foundation) * .5f, 0), new Vector3(w, h + foundation, d), wall, true, (!shop ? "siding" : "plaster"));
        Box(origin, yaw, new Vector3(0, .0f, d * .5f + .015f), new Vector3(w, .65f, .15f), "807e71", false, "brick");
        Box(origin, yaw, new Vector3(0, h + .13f, 0), new Vector3(w + .38f, .26f, d + .38f), trim);
        Box(origin, yaw, new Vector3(0, h + .31f, 0), new Vector3(w - .2f, .14f, d - .2f), "565e61", false, "roof");
        // Walkable flat roofs, parapets, skylights, chimneys and a few rooftop terraces.
        Box(origin, yaw, new Vector3(0, h + .26f, 0), new Vector3(w, .18f, d), "5f6260", true);
        foreach (var side in new[] { -1, 1 })
        {
            Box(origin, yaw, new Vector3(side * (w * .5f - .1f), h + .58f, 0), new Vector3(.22f, .65f, d), wall, true);
        }
        Box(origin, yaw, new Vector3(0, h + .58f, -d * .5f + .1f), new Vector3(w, .65f, .22f), wall, true);
        Box(origin, yaw, new Vector3(w * .23f, h + .72f, -d * .23f), new Vector3(1.5f, .85f, 1.3f), "768987");
        Box(origin, yaw, new Vector3(w * .23f, h + 1.16f, -d * .23f), new Vector3(1.65f, .08f, 1.45f), "aaa99a");
        Box(origin, yaw, new Vector3(-w * .32f, h + 1.0f, -d * .28f), new Vector3(.65f, 1.8f, .72f), "a07e69", false, "brick");
        Box(origin, yaw, new Vector3(-w * .32f, h + 1.94f, -d * .28f), new Vector3(.85f, .18f, .94f), trim);
        // Different roof silhouettes and occupied terraces break the repeated row-house mass.
        if (index % 3 == 1)
        {
            foreach (var side in new[] { -1, 1 })
            {
                var rotation = (new Basis(Vector3.Up, yaw) * new Basis(Vector3.Back, side * .27f)).GetEuler();
                _g.Add("box", Local(origin, yaw, new Vector3(side * 1.14f, h + .72f, d * .5f - .7f)), new Vector3(2.5f, .2f, 2.2f), trim, rotation);
            }
            Box(origin, yaw, new Vector3(0, h + .57f, d * .5f - .7f), new Vector3(4.6f, .8f, 1.9f), wall);
        }
        else if (index % 3 == 2)
        {
            Box(origin, yaw, new Vector3(-1, h + .46f, 1), new Vector3(5, .14f, 4), "9c8c6c", false, "siding");
            Bench(Local(origin, yaw, new Vector3(-1, h + .55f, 1)), yaw);
            foreach (var dx in new[] { -3.2f, 1.2f })
            {
                Box(origin, yaw, new Vector3(dx, h + 1.1f, 1), new Vector3(.16f, 1.4f, 4.2f), "879780");
            }
            for (int j = 0; j < 3; j += 1)
            {
                Box(origin, yaw, new Vector3(-1, h + 2.45f, -.5f + j * 1.5f), new Vector3(5, .13f, .13f), "b3b094");
            }
            foreach (var dx in new[] { -3.2f, 1.2f })
            {
                foreach (var dz in new[] { -1.1f, 3.1f })
                {
                    _g.Beam(Local(origin, yaw, new Vector3(dx, h + .5f, dz)), Local(origin, yaw, new Vector3(dx, h + 2.5f, dz)), .055f, "8f9277");
                }
            }
        }
        for (int floor = 1; floor < floors; floor += 1)
        {
            var wy = floor * 3 + 1.45f;
            foreach (var col in new[] { -1, 0, 1 })
            {
                var wx = col * w * .29f;
                var bay = (!shop && col != 0 ? .6f : .12f);
                Box(origin, yaw, new Vector3(wx, wy, d * .5f + bay * .5f), new Vector3(2.65f, 2.25f, bay + .15f), trim);
                Box(origin, yaw, new Vector3(wx, wy + .03f, d * .5f + bay + .09f), new Vector3(2.16f, 1.9f, .07f), "486269", false, "metal");
                foreach (var split in new[] { -.7f, 0, .7f })
                {
                    Box(origin, yaw, new Vector3(wx + split, wy + .04f, d * .5f + bay + .15f), new Vector3(.07f, 1.98f, .06f), trim);
                }
                Box(origin, yaw, new Vector3(wx, wy + .0f, d * .5f + bay + .16f), new Vector3(2.25f, .07f, .08f), trim);
                Box(origin, yaw, new Vector3(wx, wy - 1.22f, d * .5f + bay * .5f), new Vector3(2.95f, .18f, bay + .5f), trim);
                Box(origin, yaw, new Vector3(wx, wy + 1.23f, d * .5f + bay * .5f), new Vector3(2.95f, .16f, bay + .5f), trim);
                // Warm curtains, unevenly opened shutters, and planted window ledges.
                if ((index + col + floor) % 3 == 0)
                {
                    Box(origin, yaw, new Vector3(wx - .7f, wy, d * .5f + bay + .18f), new Vector3(.55f, 1.75f, .025f), "c9bb99");
                }
                if ((index + col) % 3 == 0)
                {
                    Box(origin, yaw, new Vector3(wx, wy - 1.05f, d * .5f + bay + .28f), new Vector3(2, .27f, .4f), "867763");
                    for (int leaf = 0; leaf < 5; leaf += 1)
                    {
                        _g.Add("leaf", Local(origin, yaw, new Vector3(wx - .8f + leaf * .4f, wy - .83f, d * .5f + bay + .35f)), new Vector3(.47f, .34f, .48f), "527653");
                    }
                }
            }
            // Continuous cornice and thin belt course prevent flat box façades.
            Box(origin, yaw, new Vector3(0, floor * 3 - .07f, d * .5f + .13f), new Vector3(w + .16f, .13f, .32f), trim);
        }
        foreach (var side in new[] { -1, 1 })
        {
            Box(origin, yaw, new Vector3(side * (w * .5f - .16f), h * .5f, d * .5f + .05f), new Vector3(.22f, h, .16f), trim);
            for (int floor = 0; floor < floors; floor += 1)
            {
                foreach (var rear in new[] { -.28f, .24f })
                {
                    Box(origin, yaw, new Vector3(side * (w * .5f + .025f), floor * 3 + 1.65f, d * rear), new Vector3(.08f, 1.55f, 1.18f), "4d6266");
                    foreach (var edge in new[] { -.65f, .65f })
                    {
                        Box(origin, yaw, new Vector3(side * (w * .5f + .09f), floor * 3 + 1.65f, d * rear + edge), new Vector3(.08f, 1.75f, .1f), trim);
                    }
                    foreach (var edge in new[] { -.85f, .85f })
                    {
                        Box(origin, yaw, new Vector3(side * (w * .5f + .1f), floor * 3 + 1.65f + edge, d * rear), new Vector3(.12f, .12f, 1.4f), trim);
                    }
                }
            }
        }
        Approach(origin, yaw, w, d, index);
        if (shop)
        {
            Shop(origin, yaw, w, d, index, trim);
        }
        else
        {
            Box(origin, yaw, new Vector3(-w * .23f, 1.15f, d * .5f + .1f), new Vector3(w * .43f, 2.2f, .12f), "7c8b88");
            for (int slat = 0; slat < 8; slat += 1)
            {
                Box(origin, yaw, new Vector3(-w * .23f, .28f + slat * .25f, d * .5f + .19f), new Vector3(w * .43f, .035f, .04f), trim);
            }
            Box(origin, yaw, new Vector3(w * .27f, 1.5f, d * .5f + .12f), new Vector3(1.4f, 2.8f, .14f), "425f5b");
            Box(origin, yaw, new Vector3(w * .27f, 2.1f, d * .5f + .21f), new Vector3(.83f, 1.15f, .05f), "9caeaa");
            Box(origin, yaw, new Vector3(w * .27f, .16f, d * .5f + .52f), new Vector3(2.1f, .3f, .9f), "a7a496", true);
            _g.Label((140 + index * 3).ToString(), Local(origin, yaw, new Vector3(w * .27f, 3.0f, d * .5f + .2f)), .8f, "4d5753", yaw, 40);
        }
        if (shop && index % 2 == 0)
        {
            FireEscape(origin, yaw, w, d, h);
        }
        // Downpipes and rear service doors reward alley exploration.
        _g.Beam(Local(origin, yaw, new Vector3(w * .45f, .2f, -d * .5f - .12f)), Local(origin, yaw, new Vector3(w * .45f, h, -d * .5f - .12f)), .055f, "606b64");
        Box(origin, yaw, new Vector3(0, 1.25f, -d * .5f - .035f), new Vector3(1.3f, 2.5f, .1f), "6d8177");
        for (int floor = 0; floor < floors; floor += 1)
        {
            foreach (var side in new[] { -1, 1 })
            {
                var rear = new Vector3(side * w * .28f, floor * 3 + 1.65f, -d * .5f - .07f);
                Box(origin, yaw, rear, new Vector3(1.7f, 1.8f, .1f), trim);
                Box(origin, yaw, rear + new Vector3(0, 0, -.08f), new Vector3(1.42f, 1.52f, .07f), "617e7c");
                Box(origin, yaw, rear + new Vector3(0, 0, -.14f), new Vector3(.07f, 1.52f, .06f), trim);
                Box(origin, yaw, rear + new Vector3(0, 0, -.14f), new Vector3(1.42f, .07f, .06f), trim);
                if ((index + floor) % 3 == 0)
                {
                    Box(origin, yaw, rear + new Vector3(0, -.88f, -.15f), new Vector3(1.9f, .28f, .35f), "9b8265");
                    for (int j = 0; j < 3; j += 1)
                    {
                        _g.Add("leaf", Local(origin, yaw, rear + new Vector3(-.6f + j * .6f, -.6f, -.22f)), new Vector3(.6f, .5f, .5f), "6f875e");
                    }
                }
            }
        }
        foreach (var side in new[] { -1, 1 })
        {
            foreach (var by in new[] { 1.5f, 4.6f })
            {
                Box(origin, yaw, new Vector3(side * (w * .5f + .025f), by, -d * .15f), new Vector3(.12f, 1.75f, 1.8f), trim);
                Box(origin, yaw, new Vector3(side * (w * .5f + .1f), by, -d * .15f), new Vector3(.04f, 1.48f, 1.5f), "607e80");
                Box(origin, yaw, new Vector3(side * (w * .5f + .15f), by, -d * .15f), new Vector3(.05f, .06f, 1.5f), trim);
                Box(origin, yaw, new Vector3(side * (w * .5f + .15f), by, -d * .15f), new Vector3(.05f, 1.48f, .07f), trim);
            }
        }
        if (index % 4 == 1)
        {
            foreach (var col in new[] { -1, 1 })
            {
                Box(origin, yaw, new Vector3(col * 2, h + .47f, 1.8f), new Vector3(2.7f, .5f, 1.1f), "aa8064");
            }
            for (int col = 0; col < 9; col += 1)
            {
                _g.Add("leaf", Local(origin, yaw, new Vector3(-3.2f + col * .8f, h + .96f, 1.8f)), new Vector3(.8f, .8f, .8f), "5f825b");
            }
        }
    }
    private void Approach(Vector3 o, float yaw, float w, float d, int index)
    {
        // Level forecourt with masonry retaining walls, then a short accessible street ramp.
        var depth = (Mathf.Abs(Mathf.Cos(yaw)) > .5f ? 2.4f : 3.8f);
        var foundation = 2.85f;
        foreach (var side in new[] { -1, 1 })
        {
            var corner = Local(o, yaw, new Vector3(side * w * .5f, 0, d * .5f + depth));
            foundation = Mathf.Max(foundation, o.Y - _map.TerrainHeight(corner.X, corner.Z) + .35f);
        }
        Box(o, yaw, new Vector3(0, -foundation * .5f + .025f, d * .5f + depth * .5f), new Vector3(w + .15f, foundation, depth), "959783", true, "brick");
        Box(o, yaw, new Vector3(0, .075f, d * .5f + depth * .5f), new Vector3(w + .25f, .12f, depth + .1f), "b8b59c");
        var a = Local(o, yaw, new Vector3(0, .17f, d * .5f + depth - .2f));
        var b = Local(o, yaw, new Vector3(0, 0, d * .5f + depth + 1.0f));
        var forward = new Basis(Vector3.Up, yaw) * Vector3.Back;
        var closest = float.PositiveInfinity;
        foreach (var street in (Mathf.Abs(forward.X) > .5f ? HarborWorld.StreetsX : HarborWorld.StreetsZ))
        {
            var distance = ((Mathf.Abs(forward.X) > .5f ? (street - o.X) * forward.X : (street - o.Z) * forward.Z));
            if (distance > 0 && distance < closest)
            {
                closest = distance;
                if (Mathf.Abs(forward.X) > .5f)
                {
                    b.X = street - forward.X * 8.0f;
                }
                else
                {
                    b.Z = street - forward.Z * 8.0f;
                }
            }
        }
        b.Y = _map.HeightAt(b.X, b.Z) + .18f;
        _g.Ribbon(new[] { a, b }, 2.2f, "b8b59c", true, false);
        foreach (var side in new[] { -1, 1 })
        {
            Box(o, yaw, new Vector3(side * (w * .5f - .35f), .36f, d * .5f + 2.1f), new Vector3(.48f, .6f, 2.7f), "778b72", true);
            for (int i = 0; i < 5; i += 1)
            {
                _g.Add("leaf", Local(o, yaw, new Vector3(side * (w * .5f - .35f), .8f, d * .5f + .95f + i * .48f)), new Vector3(.7f, .55f, .7f), new[] { "638166", "829363" }[i % 2]);
            }
            if (index % 3 == 0)
            {
                var post = Local(o, yaw, new Vector3(side * (w * .5f - .35f), .8f, d * .5f + 3.1f));
                for (int f = 0; f < 4; f += 1)
                {
                    _g.Add("sphere", (post + new Vector3(_rng.RandfRange(-.25f, .25f), _rng.RandfRange(.05f, .3f), _rng.RandfRange(-.25f, .25f))), new Vector3(.14f, .13f, .14f), "c7a079");
                }
            }
        }
        // Deepened doorway, wall lamp and a small hand-painted neighborhood tile.
        Box(o, yaw, new Vector3(w * .44f, 2.15f, d * .5f + .26f), new Vector3(.23f, .36f, .2f), "526963");
        Box(o, yaw, new Vector3(w * .44f, 2.17f, d * .5f + .38f), new Vector3(.18f, .25f, .04f), "e1cdaa");
    }
    private void CourtyardInfill()
    {
        foreach (var side in new[] { -1, 1 })
        {
            var x = (side == -1 ? -40.0f : 52.0f);
            foreach (var z in new[] { -68.0f, 7.0f })
            {
                // Inhabited pocket courts, with separate potting and reading spaces.
                foreach (var dx in new[] { -14, 14 })
                {
                    var p = _map.Point(x + dx, z);
                    _g.Box(p + new Vector3(0, -.17f, 0), new Vector3(8, .36f, 12), "aaa38a", true);
                    for (int j = 0; j < 4; j += 1)
                    {
                        _g.Box(p + new Vector3(-2.8f + j * 1.85f, .51f, 0), new Vector3(1.3f, .55f, 4.3f), "94795e");
                    }
                    for (int j = 0; j < 18; j += 1)
                    {
                        _g.Add("leaf", p + new Vector3(-3 + _rng.Randf() * 6, 1.0f, -2 + _rng.Randf() * 4), new Vector3(.65f, .85f, .65f), new[] { "6e8960", "537c64", "889466" }[j % 3]);
                    }
                    // Low workshop roofs and exterior ramps create additional cat-height routes.
                    var shed = p + new Vector3(0, 0, 5);
                    _g.Box(shed + new Vector3(0, 1.45f, 0), new Vector3(4.8f, 2.9f, 3.5f), "9eab98", true, 0, "siding");
                    _g.Box(shed + new Vector3(0, 2.97f, 0), new Vector3(5.3f, .22f, 4), "6d7e73", true);
                    _g.Box(shed + new Vector3(.7f, 1.7f, 1.8f), new Vector3(1.2f, 1.0f, .09f), "d7d2b7");
                    _g.Box(shed + new Vector3(-1.1f, 1.2f, 1.8f), new Vector3(1.1f, 2.4f, .1f), "547367");
                    _g.Ribbon(new[] { shed + new Vector3(-3.3f, .03f, -7), shed + new Vector3(-3.3f, 3.1f, -.7f) }, 1.4f, "a3a78e", true, false);
                    _g.Ribbon(new[] { shed + new Vector3(-3.3f, 3.1f, 0), shed + new Vector3(-1.6f, 3.1f, 0) }, 1.4f, "a3a78e", true, false);
                }
                var patio = _map.Point(x, z + 1);
                _g.Add("cylinder", patio, new Vector3(6.2f, .12f, 6.2f), "b1ad93");
                GardenTable(patio + new Vector3(0, .07f, 0));
                foreach (var dz in new[] { -2.5f, 2.5f })
                {
                    foreach (var dx in new[] { -2.5f, 2.5f })
                    {
                        _g.Beam(patio + new Vector3(dx, 0, dz), patio + new Vector3(dx, 2.8f, dz), .075f, "8b8f72");
                    }
                }
                for (int i = 0; i < 9; i += 1)
                {
                    _g.Box(patio + new Vector3(-2.6f + i * .65f, 2.85f, 0), new Vector3(.12f, .14f, 5.5f), "9c9b7b");
                }
                for (int i = 0; i < 18; i += 1)
                {
                    _g.Add("leaf", patio + new Vector3(_rng.RandfRange(-2.5f, 2.5f), 2.9f, _rng.RandfRange(-2.5f, 2.5f)), new Vector3(1.2f, .45f, 1.1f), "718d63");
                }
                _g.Label("A LITTLE QUIET", patio + new Vector3(0, 2.32f, 2.57f), 2, "e0d3ac", 0, 48);
            }
        }
        // Gravel driveway ribbons and garden walls connect every court to its block.
        foreach (var x in new[] { -52.0f, -24.0f, 40.0f, 68.0f })
        {
            foreach (var bounds in new[] { new[] { -77, -58 }, new[] { -7, 24 } })
            {
                var path = new List<Vector3>();
                for (int z = bounds[0]; z < bounds[1]; z += 1)
                {
                    path.Add(_map.Point(x, z, .055f));
                }
                _g.Ribbon(path, 2.2f, "b3b197", true);
            }
        }
        // Hand-laid sidewalk joints, drain grates, road repairs, hydrants and bicycle stands.
        foreach (var x in new[] { -76.0f, 8.0f, 90.0f })
        {
            for (int z = -109; z < 131; z += 2)
            {
                foreach (var side in new[] { -1, 1 })
                {
                    _g.Ribbon(new[] { _map.Point(x + side * 5.5f, z, .187f), _map.Point(x + side * 8.1f, z, .187f) }, .022f, "919b8d");
                }
            }
            for (int z = -89; z < 119; z += 23)
            {
                _g.Add("cylinder", _map.Point(x + 1.8f, z, .049f), new Vector3(.68f, .025f, .68f), "626f69");
                _g.Ribbon(new[] { _map.Point(x - 3.7f, z + 1, .046f), _map.Point(x - 3.7f, z + 4, .046f) }, 1.4f, "536166");
                foreach (var side in new[] { -1, 1 })
                {
                    var p = _map.Point(x + side * 5.15f, z, .052f);
                    _g.Box(p, new Vector3(.35f, .026f, .65f), "596b64");
                    for (int stripe = 0; stripe < 6; stripe += 1)
                    {
                        _g.Box(p + new Vector3(0, .016f, -.26f + stripe * .105f), new Vector3(.33f, .015f, .028f), "a6aa96");
                    }
                }
            }
            foreach (var z in new[] { -83, 12, 76 })
            {
                var p = _map.Point(x + 7.7f, z);
                _g.Add("cylinder", p + new Vector3(0, .38f, 0), new Vector3(.28f, .76f, .28f), "bd9871");
                _g.Add("sphere", p + new Vector3(0, .81f, 0), new Vector3(.31f, .21f, .31f), "b08a66");
                _g.Beam(p + new Vector3(-.22f, .53f, 0), p + new Vector3(.22f, .53f, 0), .08f, "b08a66");
            }
        }
    }
    private void Shop(Vector3 o, float yaw, float w, float d, int index, string trim)
    {
        var names = new[] { "BAY LEAF", "SLOW MORNING", "PAPER & PINE", "LITTLE CURRENT", "SUNROOM", "THE READING ROOM", "SALT & STEM", "WARM LOAF" };
        var colors = new[] { "557b70", "a56855", "c2a46c", "5d7987" };
        var color = colors[index % 4];
        foreach (var x in new[] { -w * .27f, w * .27f })
        {
            Box(o, yaw, new Vector3(x, 1.5f, d * .5f + .07f), new Vector3(w * .43f, 2.25f, .1f), "526d70");
            foreach (var dx in new[] { -w * .2f, w * .2f })
            {
                Box(o, yaw, new Vector3(x + dx, 1.4f, d * .5f + .15f), new Vector3(.12f, 2.7f, .16f), trim);
            }
            Box(o, yaw, new Vector3(x, .3f, d * .5f + .15f), new Vector3(w * .44f, .45f, .2f), color);
            foreach (var pane in new[] { -1, 0, 1 })
            {
                var pane_x = x + pane * w * .135f;
                Box(o, yaw, new Vector3(pane_x, 1.6f, d * .5f + .135f), new Vector3(w * .125f, 1.89f, .024f), new[] { "567678", "648081", "4a686f" }[(pane + index + 1) % 3]);
                Box(o, yaw, new Vector3(pane_x - w * .066f, 1.6f, d * .5f + .22f), new Vector3(.05f, 1.95f, .06f), trim);
                Box(o, yaw, new Vector3(pane_x - .2f, 2.09f, d * .5f + .19f), new Vector3(.16f, .68f, .018f), "9fb6ad");
                // Pendant lamps and readable display objects form a shallow shop interior.
                _g.Beam(Local(o, yaw, new Vector3(pane_x, 2.6f, d * .5f + .22f)), Local(o, yaw, new Vector3(pane_x, 2.3f, d * .5f + .22f)), .012f, "847c65");
                _g.Add("sphere", Local(o, yaw, new Vector3(pane_x, 2.28f, d * .5f + .23f)), new Vector3(.32f, .16f, .08f), "d9c495");
                Box(o, yaw, new Vector3(pane_x, 1.02f, d * .5f + .23f), new Vector3(w * .11f, .22f, .035f), "bca477");
                for (int item = 0; item < 3; item += 1)
                {
                    if (index % 2 == 0)
                    {
                        _g.Add("sphere", Local(o, yaw, new Vector3(pane_x - .32f + item * .32f, 1.21f, d * .5f + .27f)), new Vector3(.25f, .14f, .08f), new[] { "d3b581", "b99264", "d8bf92" }[item]);
                    }
                    else
                    {
                        Box(o, yaw, new Vector3(pane_x - .32f + item * .32f, 1.32f, d * .5f + .27f), new Vector3(.2f, .48f + item * .07f, .08f), new[] { "b3986c", "779894", "bf9b85" }[item]);
                    }
                }
            }
            Box(o, yaw, new Vector3(x, 1.92f, d * .5f + .24f), new Vector3(w * .4f, .055f, .08f), trim);
            // Display shelves, jars and a low counter behind the glass plane.
            Box(o, yaw, new Vector3(x, .84f, d * .5f + .18f), new Vector3(w * .39f, .1f, .04f), "d9c29c");
            for (int j = 0; j < 5; j += 1)
            {
                Box(o, yaw, new Vector3(x - w * .16f + j * w * .08f, 1.12f, d * .5f + .2f), new Vector3(.35f, .38f, .06f), new[] { "b9a371", "cca67e", "8aaba4" }[j % 3]);
            }
        }
        Box(o, yaw, new Vector3(0, 1.4f, d * .5f + .13f), new Vector3(1.2f, 2.65f, .15f), color);
        Box(o, yaw, new Vector3(0, 1.85f, d * .5f + .23f), new Vector3(.9f, 1.35f, .04f), "98b5b2");
        Box(o, yaw, new Vector3(0, 3.32f, d * .5f + .22f), new Vector3(w - .25f, .65f, .27f), color);
        Box(o, yaw, new Vector3(0, 2.55f, d * .5f + 1.77f), new Vector3(w * .7f, .6f, .1f), color);
        _g.Label(names[index % names.Length], Local(o, yaw, new Vector3(0, 2.55f, d * .5f + 1.835f)), w * .63f, "f6e8c9", yaw);
        // Broad fabric canopy with original striped pattern made from narrow primitives.
        _g.BoxCollision(Local(o, yaw, new Vector3(0, 2.75f, d * .5f + .88f)), new Vector3(w, .13f, 1.7f), new Vector3(.18f, yaw, 0));
        for (int stripe = 0; stripe < 16; stripe += 1)
        {
            var x = -w * .5f + (stripe + .5f) * w / 16;
            _g.Add("box", Local(o, yaw, new Vector3(x, 2.75f, d * .5f + .88f)), new Vector3(w / 16, .1f, 1.7f), (stripe % 2 == 0 ? color : "e8d9ba"), new Vector3(.18f, yaw, 0));
            Box(o, yaw, new Vector3(x, 2.5f, d * .5f + 1.7f), new Vector3(w / 16, .35f, .08f), (stripe % 2 == 0 ? color : "e8d9ba"));
        }
        foreach (var side in new[] { -1, 1 })
        {
            var at = Local(o, yaw, new Vector3(side * w * .35f, .15f, d * .5f + 1.65f));
            if (index % 3 != 2 || side == -1)
            {
                CafeTable(at, yaw);
            }
            else
            {
                Planter(at, 1.1f);
            }
        }
        Box(o, yaw, new Vector3(w * .22f, .5f, d * .5f + .72f), new Vector3(1.8f, 1f, .6f), "9e815c");
        for (int shelf = 0; shelf < 2; shelf += 1)
        {
            for (int item = 0; item < 5; item += 1)
            {
                var at = Local(o, yaw, new Vector3(w * .22f - .65f + item * .32f, .85f + shelf * .32f, d * .5f + 1.04f));
                _g.Add("sphere", at, new Vector3(.27f, .24f, .25f), new[] { "d8a950", "c0824d", "a4ac6c" }[item % 3]);
            }
        }
        Box(o, yaw, new Vector3(-w * .42f, 1.55f, d * .5f + .22f), new Vector3(.85f, 1.18f, .08f), "365f51");
        _g.Label("FRESH DAILY\nCOFFEE · TEA\nBREAD\n& GOOD BOOKS", Local(o, yaw, new Vector3(-w * .42f, 1.55f, d * .5f + .28f)), .7f, "ead4a6", yaw, 48);
        var pot = Local(o, yaw, new Vector3(-w * .44f, .46f, d * .5f + 1.1f));
        _g.Add("cylinder", pot, new Vector3(.65f, .9f, .65f), "b4815d");
        _g.Add("leaf", pot + Vector3.Up * .8f, new Vector3(1.1f, 1.6f, 1.1f), "73934c");
        var board = Local(o, yaw, new Vector3(w * .44f, .75f, d * .5f + 2.35f));
        _g.Box(board, new Vector3(.75f, 1.1f, .13f), "3f625a", false, yaw);
        _g.Label("TAKE IT\nSLOW", board + new Basis(Vector3.Up, yaw) * new Vector3(0, 0, .075f), .55f, "e9dcc0", yaw, 48);
    }
    private void FireEscape(Vector3 o, float yaw, float w, float d, float h)
    {
        for (int floor = 1; floor < (int)(h / 3); floor += 1)
        {
            var y = floor * 3 + .27f;
            var z = d * .5f + 1.05f;
            Box(o, yaw, new Vector3(0, y, z), new Vector3(4.2f, .11f, 1.5f), "495b59", true);
            foreach (var x in new[] { -2.0f, 2.0f })
            {
                _g.Beam(Local(o, yaw, new Vector3(x, y, z - .65f)), Local(o, yaw, new Vector3(x, y + .9f, z - .65f)), .04f, "495b59");
            }
            for (int j = 0; j < 11; j += 1)
            {
                _g.Beam(Local(o, yaw, new Vector3(-2 + j * .4f, y, z + .7f)), Local(o, yaw, new Vector3(-2 + j * .4f, y + .9f, z + .7f)), .025f, "495b59");
            }
            _g.Beam(Local(o, yaw, new Vector3(-2, y + .9f, z + .7f)), Local(o, yaw, new Vector3(2, y + .9f, z + .7f)), .035f, "495b59");
            for (int j = 0; j < 12; j += 1)
            {
                Box(o, yaw, new Vector3(-1.5f + j * .24f, y + .12f + j * .23f, z), new Vector3(.45f, .08f, 1.1f), "495b59");
            }
            // The existing treads sit on stringers, with a continuous handrail and wall brackets.
            foreach (var side in new[] { -1, 1 })
            {
                var a = new Vector3(-1.65f, y + .03f, z + side * .58f);
                var b = new Vector3(1.32f, y + 2.89f, z + side * .58f);
                _g.Beam(Local(o, yaw, a), Local(o, yaw, b), .045f, "495b59");
                _g.Beam(Local(o, yaw, a + Vector3.Up * .94f), Local(o, yaw, b + Vector3.Up * .94f), .032f, "495b59");
                for (int step = 0; step < 5; step += 1)
                {
                    var p = a.Lerp(b, step / 4f);
                    _g.Beam(Local(o, yaw, p), Local(o, yaw, p + Vector3.Up * .94f), .023f, "495b59");
                }
                _g.Beam(Local(o, yaw, new Vector3(side * 1.7f, y - .75f, d * .5f)), Local(o, yaw, new Vector3(side * 1.7f, y, z + .55f)), .04f, "495b59");
            }
        }
    }
    private void CafeTable(Vector3 at, float yaw = 0)
    {
        _g.Add("cylinder", at + new Vector3(0, .72f, 0), new Vector3(.82f, .08f, .82f), "bba37b");
        _g.Beam(at, at + new Vector3(0, .69f, 0), .06f, "536462");
        foreach (var side in new[] { -1, 1 })
        {
            var p = at + new Basis(Vector3.Up, yaw) * new Vector3(side * .75f, 0, 0);
            _g.Box(p + new Vector3(0, .42f, 0), new Vector3(.46f, .08f, .43f), "788e80");
            _g.Box(p + new Vector3(0, .73f, -.2f), new Vector3(.46f, .55f, .05f), "788e80");
            foreach (var dx in new[] { -.16f, .16f })
            {
                foreach (var dz in new[] { -.15f, .15f })
                {
                    _g.Beam(p + new Vector3(dx, 0, dz), p + new Vector3(dx, .42f, dz), .018f, "536462");
                }
            }
        }
        _g.Add("cylinder", at + new Vector3(0, .83f, 0), new Vector3(.13f, .18f, .13f), "e6dcc6");
    }
    private void Planter(Vector3 at, float size)
    {
        _g.Box(at + new Vector3(0, .25f, 0), new Vector3(size, .5f, size), "a98568", true);
        for (int i = 0; i < 4; i += 1)
        {
            _g.Add("leaf", at + new Vector3(_rng.RandfRange(-.3f, .3f), .75f, _rng.RandfRange(-.3f, .3f)), new Vector3(.6f, .7f, .6f), "688360");
        }
    }
    private void GardensAndRoutes()
    {
        // Long internal alleys connect the cross streets and reveal occupied back gardens.
        foreach (var x in new[] { -38.0f, 53.0f })
        {
            foreach (var z0 in new[] { -76.0f, -8.0f })
            {
                var path = new List<Vector3>();
                for (int z = (int)(z0); z < (int)(z0 + 30); z += 1)
                {
                    path.Add(_map.Point(x, z, .07f));
                }
                _g.Ribbon(path, 3.0f, "b6a786", true);
                foreach (var side in new[] { -1, 1 })
                {
                    for (int z = (int)(z0); z < (int)(z0 + 30); z += 4)
                    {
                        var p = _map.Point(x + side * 3, z);
                        _g.Box(p + new Vector3(0, .65f, 0), new Vector3(.12f, 1.3f, .12f), "9b9f8b");
                        _g.Box(p + new Vector3(0, .6f, 0), new Vector3(.06f, .07f, 4), "b2af96");
                    }
                }
                for (int i = 0; i < 6; i += 1)
                {
                    Planter(_map.Point(x + ((i % 2 != 0 ? -1 : 1)) * 5, z0 + 3 + i * 4), 1.4f);
                }
                // Laundry lines, a garden potting bench and a reading nook.
                var a = _map.Point(x - 4, z0 + 12, 2.7f);
                var b = _map.Point(x + 4, z0 + 12, 2.7f);
                _g.Beam(a, b, .018f, "78847d");
                for (int i = 0; i < 6; i += 1)
                {
                    _g.Cloth(a.Lerp(b, (i + 1) / 7.0f), new Vector2(.65f, .74f), new[] { "eee2c6", "c3cfc4", "afbac7" }[i % 3]);
                }
                Bench(_map.Point(x + 4, z0 + 21), Mathf.Pi * .5f);
            }
        }
        // A real stair street on a smooth collider reaches the wooded hilltop.
        foreach (var x in new[] { -38.0f, -104.0f })
        {
            var z0 = 47.0f;
            var z1 = 91.0f;
            var a = _map.Point(x, z0, .1f);
            var b = _map.Point(x, z1, .1f);
            var rise = b.Y - a.Y;
            var count = Mathf.CeilToInt(rise / .16f);
            var run = (z1 - z0) / count;
            for (int i = 0; i < count; i += 1)
            {
                var y = a.Y + (i + 1) * rise / count;
                _g.Box(new Vector3(x, y - .1f, z0 + (i + .5f) * run), new Vector3(3.4f, .2f, run + .02f), "b9b9a7");
            }
            _g.Ribbon(new[] { _map.Point(x, z0 - 1, .015f), a, b, _map.Point(x, z1 + 1, .015f) }, 3.45f, "b9b9a7", true, false);
            foreach (var side in new[] { -1, 1 })
            {
                _g.Beam(a + new Vector3(side * 1.6f, .95f, 0), b + new Vector3(side * 1.6f, .95f, 0), .045f, "586c64");
                for (int i = 0; i < 12; i += 1)
                {
                    var p = a.Lerp(b, i / 11.0f) + new Vector3(side * 1.6f, 0, 0);
                    _g.Beam(p, p + Vector3.Up * .95f, .035f, "586c64");
                }
            }
            _g.Label("CYPRESS STEPS", a + new Vector3(-2.6f, 1.2f, 0), 1.6f, "586c64", 0);
        }
        // A planted retaining edge gives the park-facing residential lane an owned boundary.
        for (int x = -18; x < 78; x += 3)
        {
            var at = _map.Point(x, 54);
            _g.Box(at + new Vector3(0, .34f, 0), new Vector3(2.95f, .68f, .5f), "8f9985", true, 0, "brick");
            for (int j = 0; j < 3; j += 1)
            {
                _g.Add("leaf", at + new Vector3(-.9f + j * .9f, .9f, 0), new Vector3(1.1f, .75f, .95f), new[] { "6d865f", "8b9665" }[j % 2]);
            }
        }
        // Upper plaza: shelter, tiled turning circle, neighborhood noticeboard.
        var plaza = _map.Point(8, 96);
        foreach (var x in new[] { -7, 7 })
        {
            Bench(plaza + new Vector3(x, 0, 1), (x < 0 ? -Mathf.Pi * .5f : Mathf.Pi * .5f));
        }
        _g.Box(_map.Point(-5, 84, 1.1f), new Vector3(1.8f, 1.4f, .15f), "5c7465", true);
        _g.Label("HARBOR HILLS\nGARDEN WALK\nSUNDAYS", _map.Point(-5, 84, 1.1f) + new Vector3(0, 0, .09f), 1.5f, "ecdfbe", 0, 56);
        // A short ramp onto a low garden pavilion gives the cat a roof route.
        var pavilion = _map.Point(-56, 62);
        _g.Box(pavilion + new Vector3(0, 1.25f, 0), new Vector3(7, 2.5f, 6), "b6a58b", true);
        _g.Box(pavilion + new Vector3(0, 2.6f, 0), new Vector3(7.6f, .2f, 6.6f), "738b7c", true);
        _g.Ribbon(new[] { _map.Point(-56, 52, .02f), pavilion + new Vector3(0, 2.72f, -3.3f) }, 2.4f, "abac91", true, false);
        Bench(pavilion + new Vector3(0, 2.73f, 0), Mathf.Pi);
    }
    private void Bench(Vector3 at, float yaw)
    {
        for (int i = 0; i < 4; i += 1)
        {
            _g.Box(at + new Basis(Vector3.Up, yaw) * new Vector3(0, .45f, -.24f + i * .15f), new Vector3(1.75f, .08f, .12f), "a29573", false, yaw);
        }
        for (int i = 0; i < 3; i += 1)
        {
            _g.Box(at + new Basis(Vector3.Up, yaw) * new Vector3(0, .75f + i * .13f, -.35f), new Vector3(1.75f, .1f, .07f), "a29573", false, yaw);
        }
        foreach (var x in new[] { -.65f, .65f })
        {
            _g.Beam(at + new Basis(Vector3.Up, yaw) * new Vector3(x, 0, 0), at + new Basis(Vector3.Up, yaw) * new Vector3(x, .5f, 0), .04f, "566961");
        }
    }
    private void StreetFurniture()
    {
        foreach (var x in new[] { -76.0f, 8.0f, 90.0f })
        {
            for (int z = -94; z < 130; z += 22)
            {
                var p = _map.Point(x - 7.7f, z);
                _g.Beam(p, p + Vector3.Up * 5.3f, .08f, "4c6562");
                _g.Beam(p + Vector3.Up * 5.2f, p + new Vector3(1, 5.5f, 0), .055f, "4c6562");
                _g.Add("sphere", p + new Vector3(1, 5.35f, 0), new Vector3(.55f, .35f, .55f), "dfd2ad");
                if (z % 3 == 0)
                {
                    Bench(_map.Point(x + 7.5f, z), Mathf.Pi * .5f);
                }
                // Utility poles and sagging service wires.
                var pole = _map.Point(x + 8.3f, z);
                _g.Beam(pole, pole + Vector3.Up * 8, .12f, "8c7960");
                _g.Box(pole + new Vector3(0, 7.45f, 0), new Vector3(2.8f, .14f, .16f), "8c7960");
                if (z < 126)
                {
                    foreach (var dx in new[] { -1, 0, 1 })
                    {
                        var a = pole + new Vector3(dx, 7.6f, 0);
                        var b = _map.Point(x + 8.3f, z + 22, 7.6f) + new Vector3(dx, 0, 0);
                        var prev = a;
                        for (int i = 1; i < 13; i += 1)
                        {
                            var t = i / 12.0f;
                            var next = a.Lerp(b, t) - Vector3.Up * Mathf.Sin(t * Mathf.Pi) * .65f;
                            _g.Beam(prev, next, .014f, "58645f");
                            prev = next;
                        }
                    }
                }
                if (x != 8 && z % 2 == 0)
                {
                    Car(_map.Point(x + 3.6f, z + 7, .04f), 0, new[] { "879f9e", "b09d82", "b78270", "d1c6ab" }[Mathf.PosMod(z, 4)]);
                }
            }
        }
        foreach (var z in new[] { -101.0f, -32.0f, 46.0f, 91.0f })
        {
            var p = _map.Point(14.5f, z);
            _g.Beam(p, p + Vector3.Up * 2.9f, .055f, "576c65");
            _g.Box(p + new Vector3(0, 2.4f, 0), new Vector3(.9f, .75f, .1f), "718a7c");
            _g.Label("CABLE\nLINE", p + new Vector3(0, 2.42f, .06f), .7f, "f3e2b8", 0, 52);
            Bench(_map.Point(17.5f, z), Mathf.Pi);
            _g.Box(_map.Point(17.4f, z, 2.55f), new Vector3(3.8f, .12f, 1.8f), "a2b4a8");
            foreach (var dx in new[] { -1.65f, 1.65f })
            {
                _g.Beam(_map.Point(17.4f + dx, z - .7f), _map.Point(17.4f + dx, z - .7f, 2.5f), .06f, "576c65");
            }
        }
        foreach (var p in new[] { _map.Point(-69, -34), _map.Point(16, -30), _map.Point(84, 42) })
        {
            _g.Add("cylinder", p + new Vector3(0, .48f, 0), new Vector3(.65f, .96f, .65f), "5d796a");
            _g.Add("cylinder", p + new Vector3(1.1f, .25f, 0), new Vector3(.26f, .5f, .26f), "b08c68");
            _g.Beam(p + new Vector3(-.5f, 0, .4f), p + new Vector3(-.5f, 3.1f, .4f), .045f, "506a62");
            _g.Box(p + new Vector3(-.5f, 2.95f, .4f), new Vector3(1.95f, .33f, .1f), "506a62");
            _g.Label("CYPRESS WAY", p + new Vector3(-.5f, 2.95f, .46f), 1.7f, "e8ddbf", 0, 64);
        }
    }
    private void Car(Vector3 at, float yaw, string color)
    {
        // Compact fictional neighborhood cars, parked clear of crossings.
        _g.Box(at + new Vector3(0, .62f, 0), new Vector3(1.7f, .65f, 3.8f), color, true, yaw);
        _g.Box(at + new Vector3(0, 1.13f, .15f), new Vector3(1.5f, .7f, 1.9f), color, false, yaw);
        _g.Box(at + new Vector3(0, 1.2f, 1.13f), new Vector3(1.35f, .48f, .035f), "6b9095", false, yaw);
        _g.Box(at + new Vector3(0, 1.2f, -.83f), new Vector3(1.35f, .48f, .035f), "6b9095", false, yaw);
        foreach (var side in new[] { -1, 1 })
        {
            _g.Box(at + new Vector3(side * .76f, 1.22f, .15f), new Vector3(.03f, .43f, 1.58f), "6b9095", false, yaw);
            foreach (var z in new[] { -1.18f, 1.15f })
            {
                _g.Add("cylinder", at + new Vector3(side * .84f, .38f, z), new Vector3(.57f, .19f, .57f), "3d4749", new Vector3(0, 0, Mathf.Pi * .5f));
            }
            _g.Box(at + new Vector3(side * .58f, .72f, -1.91f), new Vector3(.35f, .2f, .05f), "d8cfa5");
        }
    }
    private void Waterfront()
    {
        for (int x = -160; x < 171; x += 7)
        {
            var p = new Vector3(x, 3.25f, -119);
            _g.Beam(p, p + Vector3.Up * 1.02f, .045f, "617a72");
            if (x < 166)
            {
                foreach (var h in new[] { .48f, .97f })
                {
                    _g.Beam(p + Vector3.Up * h, p + new Vector3(7, h, 0), .025f, "617a72");
                }
            }
        }
        foreach (var x in new[] { -149, -114, -53, -9, 39, 88, 141 })
        {
            Bench(_map.Point(x, -112), 0);
            if (x % 3 == 0)
            {
                Planter(_map.Point(x + 3, -112), 1.2f);
            }
        }
        // Small waterfront gathering places interrupt the promenade's long rhythm.
        for (int x = -170; x < 173; x += 2)
        {
            _g.Ribbon(new[] { _map.Point(x, -117, .102f), _map.Point(x, -108.8f, .102f) }, .018f, "a0aa9c");
        }
        foreach (var z in new[] { -116.0f, -110.0f })
        {
            var joints = new List<Vector3>();
            for (int x = -170; x < 173; x += 2)
            {
                joints.Add(_map.Point(x, z, .102f));
            }
            _g.Ribbon(joints, .025f, "a0aa9c");
        }
        var deck = new Vector3(-25, 3.22f, -113.5f);
        for (int i = 0; i < 55; i += 1)
        {
            _g.Box(deck + new Vector3(-6.6f + i * .245f, 0, 0), new Vector3(.23f, .18f, 7.6f), new[] { "a49b7e", "aca38a", "9c967b" }[i % 3]);
        }
        CafeTable(deck + new Vector3(-3, .1f, 0));
        CafeTable(deck + new Vector3(3, .1f, 0));
        Bench(deck + new Vector3(0, .1f, -2.2f), 0);
        _g.Box(deck + new Vector3(0, .64f, -2.05f), new Vector3(.4f, .09f, .3f), "bc9a76");
        _g.Box(deck + new Vector3(.03f, .7f, -2.05f), new Vector3(.36f, .04f, .27f), "e0d5b3");
        var kiosk = _map.Point(47, -110);
        _g.Box(kiosk + new Vector3(0, 1.35f, 0), new Vector3(3.8f, 2.7f, 2.5f), "78968a", true, 0, "siding");
        _g.Box(kiosk + new Vector3(0, 2.83f, 0), new Vector3(4.4f, .25f, 3.1f), "b7baa0");
        _g.Box(kiosk + new Vector3(0, 1.48f, -1.28f), new Vector3(2.5f, 1.35f, .08f), "456b70");
        _g.Box(kiosk + new Vector3(0, .87f, -1.47f), new Vector3(3.0f, .14f, .5f), "b3aa8c");
        _g.Box(kiosk + new Vector3(0, 2.47f, -1.29f), new Vector3(3.3f, .38f, .08f), "496c60");
        _g.Label("BAY POST", kiosk + new Vector3(0, 2.47f, -1.35f), 2.3f, "e9d6ae", Mathf.Pi);
        for (int i = 0; i < 6; i += 1)
        {
            _g.Box(kiosk + new Vector3(-1 + i * .4f, 1.16f, -1.38f), new Vector3(.31f, .35f, .07f), new[] { "c1b497", "a4b7ab", "bd9a7c" }[i % 3]);
        }
        foreach (var side in new[] { -1, 1 })
        {
            Planter(kiosk + new Vector3(side * 2.5f, 0, 0), 1.2f);
            _g.Box(kiosk + new Vector3(side * 1.35f, 1.48f, -1.32f), new Vector3(.12f, 1.45f, .1f), "dfd6b7");
        }
        // A sheltered bicycle rack and a few rope bollards frame the boat-house approach.
        foreach (var x in new[] { -103, -101.8f, -100.6f, -99.4f })
        {
            var p = _map.Point(x, -112);
            _g.Beam(p + new Vector3(-.3f, 0, 0), p + new Vector3(-.3f, .75f, 0), .03f, "586f64");
            _g.Beam(p + new Vector3(.3f, 0, 0), p + new Vector3(.3f, .75f, 0), .03f, "586f64");
            _g.Beam(p + new Vector3(-.3f, .75f, 0), p + new Vector3(.3f, .75f, 0), .03f, "586f64");
        }
        foreach (var x in new[] { -116, -111, -105, -100 })
        {
            var p = new Vector3(x, 3.2f, -118);
            _g.Add("cylinder", p + new Vector3(0, .3f, 0), new Vector3(.32f, .6f, .32f), "738578");
            _g.Add("sphere", p + new Vector3(0, .62f, 0), new Vector3(.43f, .17f, .43f), "738578");
            if (x != -100)
            {
                var previous = p + Vector3.Up * .5f;
                for (int i = 1; i < 9; i += 1)
                {
                    var next = p + new Vector3(i * .625f, .5f - Mathf.Sin(i / 8.0f * Mathf.Pi) * .27f, 0);
                    _g.Beam(previous, next, .025f, "ad9c76");
                    previous = next;
                }
            }
        }
        // Quiet working pier, rope bollards, weathered shed and stacked lobster pots.
        _g.Box(new Vector3(-114, 2.3f, -141), new Vector3(12, .7f, 45), "989d8e", true, 0, "siding");
        for (int z = -161; z < -119; z += 5)
        {
            foreach (var x in new[] { -119, -109 })
            {
                _g.Add("cylinder", new Vector3(x, .1f, z), new Vector3(.6f, 5, .6f), "727e72");
            }
        }
        _g.Box(new Vector3(-114, 4.1f, -134), new Vector3(5.5f, 3, 6), "8baba1", true, 0, "siding");
        _g.Box(new Vector3(-114, 5.8f, -134), new Vector3(6.2f, .3f, 6.6f), "75837e");
        for (int i = 0; i < 6; i += 1)
        {
            _g.Box(new Vector3(-117 + i % 2 * 1.2f, 2.95f + Mathf.FloorToInt(i / 2) * .5f, -147), new Vector3(1, .45f, .8f), "8a8064");
        }
        _g.Label("TIDELINE\nBOAT HOUSE", new Vector3(-114, 4.25f, -130.94f), 3.3f, "eee0bc", 0);
    }
    private void GardenTable(Vector3 at)
    {
        for (int i = 0; i < 6; i += 1)
        {
            _g.Box(at + new Vector3(-.55f + i * .22f, .78f, 0), new Vector3(.19f, .1f, 2.1f), "b39d76");
        }
        foreach (var x in new[] { -.42f, .42f })
        {
            foreach (var z in new[] { -.8f, .8f })
            {
                _g.Beam(at + new Vector3(x, 0, z), at + new Vector3(x, .75f, z), .035f, "566c5b");
            }
        }
        foreach (var side in new[] { -1, 1 })
        {
            foreach (var z in new[] { -.65f, .65f })
            {
                var p = at + new Vector3(side * 1.05f, 0, z);
                _g.Box(p + Vector3.Up * .43f, new Vector3(.55f, .08f, .55f), "799077");
                _g.Box(p + new Vector3(side * .23f, .73f, 0), new Vector3(.07f, .6f, .55f), "799077");
                foreach (var dx in new[] { -.2f, .2f })
                {
                    foreach (var dz in new[] { -.2f, .2f })
                    {
                        _g.Beam(p + new Vector3(dx, 0, dz), p + new Vector3(dx, .42f, dz), .025f, "566c5b");
                    }
                }
            }
        }
        _g.Add("cylinder", at + new Vector3(0, .99f, 0), new Vector3(.26f, .32f, .26f), "b68760");
        _g.Add("leaf", at + new Vector3(0, 1.23f, 0), new Vector3(.45f, .45f, .45f), "75904c");
        _g.Box(at + new Vector3(.2f, .86f, .67f), new Vector3(.43f, .06f, .57f), "9c8265");
        _g.Box(at + new Vector3(.2f, .9f, .67f), new Vector3(.39f, .025f, .54f), "e0d0aa");
    }
}
