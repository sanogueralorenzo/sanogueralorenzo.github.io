using Godot;

namespace CozySora;

public sealed class HarborDetails
{
    private HarborWorld _map = null!;
    private HarborGeometry _g = null!;
    private readonly RandomNumberGenerator _rng = new();
    public void Build(HarborWorld world, HarborGeometry geometry)
    {
        _map = world;
        _g = geometry;
        _rng.Seed = 57329;
        StreetGardens();
        ShopsAndHomes();
        HillsideBorders();
        HarborPlaces();
    }
    private void StreetGardens()
    {
        // The outer edge leaves the two-metre pavement route and every crossing open.
        foreach (var x in new[] { -.7f, 17.3f })
        {
            foreach (var z in new[] { -91.0f, -80.0f, -51.0f, -20.0f, 25.0f, 65.0f, 120.0f })
            {
                Bed(_map.Point(x, z, .08f), new Vector2(1.05f, 3.8f), (int)(z), true);
            }
        }
        foreach (var z in new[] { -74f, -57f, -12f, 24f, 70f })
        {
            Bed(_map.Point(12.65f, z, .03f), new Vector2(.95f, 3.4f), (int)(z), true);
        }
        foreach (var x in new[] { -83.8f, 98.1f })
        {
            foreach (var z in new[] { -76.0f, -54.0f, -9.0f, 24.0f, 69.0f, 119.0f })
            {
                Bed(_map.Point(x, z, .15f), new Vector2(.8f, 3.1f), (int)(z + 10), true);
            }
        }
        // Frontages receive distinct low gardens rather than a continuous hedge wall.
        foreach (var z in new[] { -95.7f, -37.3f, 39.0f })
        {
            foreach (var x in new[] { -63.0f, -47.0f, -19.0f, 32.0f, 60.0f, 75.0f })
            {
                Bed(_map.Point(x, z, .12f), new Vector2(3.0f, .8f), (int)(x + z), true);
            }
        }
        foreach (var x in new[] { -65.0f, -32.0f, 38.0f, 67.0f, 113.0f })
        {
            Bed(_map.Point(x, -110.0f), new Vector2(4.3f, 1.15f), (int)(x), true);
        }
        // An irregular groundcover ribbon occupies formerly naked strips beside homes.
        foreach (var z in new[] { -93.0f, -38.0f, 39.0f })
        {
            for (int i = 0; i < 150; i += 1)
            {
                var x = _rng.RandfRange(-66, 79);
                if (x > -5 && x < 21)
                {
                    continue;
                }
                var at = _map.Point(x, z + _rng.RandfRange(-.45f, .45f), .1f);
                _g.Add("leaf", at + Vector3.Up * .18f, new Vector3(.75f, .38f, .65f), new[] { "668748", "78934d", "47754a" }[i % 3]);
            }
        }
        foreach (var z in new[] { -78.0f, -1.0f, 78.0f })
        {
            Bicycle(_map.Point(17.1f, z, .15f), Mathf.Pi * .5f, "ba8e65");
            _g.Box(_map.Point(-.8f, z, 1.0f), new Vector3(.38f, 1.6f, .48f), "486b62");
            _g.Label("BAY\nWALK", _map.Point(-.8f, z, 1.02f) + new Vector3(0, 0, .25f), .31f, "e9d9ad", 0, 36);
        }
    }
    private void Bed(Vector3 at, Vector2 size, int index, bool raised = false)
    {
        var lift = (raised ? .24f : .0f);
        if (raised)
        {
            _g.Box(at + new Vector3(0, .16f, 0), new Vector3(size.X, .32f, size.Y), "8f8c72", false, 0, "brick");
            _g.Box(at + new Vector3(0, .33f, 0), new Vector3(size.X + .08f, .08f, size.Y + .08f), "c1b69b");
            _g.Box(at + new Vector3(0, .38f, 0), new Vector3(size.X - .1f, .025f, size.Y - .1f), "685f43");
        }
        var count = Math.Max(7, (int)(size.X * size.Y * 3));
        for (int i = 0; i < count; i += 1)
        {
            var p = (at + new Vector3(_rng.RandfRange(-.43f, .43f) * size.X, lift + .24f, _rng.RandfRange(-.43f, .43f) * size.Y));
            _g.Add("leaf", p, new Vector3(.65f, .7f, .65f), new[] { "5f8446", "8b984d", "42774e" }[i % 3]);
            if (i % 2 == 0)
            {
                Flower(p + Vector3.Up * _rng.RandfRange(.15f, .35f), new[] { "dea34b", "dccdc1", "b08ca6" }[Mathf.PosMod(index, 3)]);
            }
        }
    }
    private void Flower(Vector3 p, string color)
    {
        _g.Beam(p - Vector3.Up * .35f, p, .011f, "668046");
        for (int i = 0; i < 5; i += 1)
        {
            var angle = i * Mathf.Tau / 5;
            _g.Add("sphere", p + new Vector3(Mathf.Cos(angle) * .08f, 0, Mathf.Sin(angle) * .08f), new Vector3(.13f, .05f, .13f), color);
        }
        _g.Add("sphere", p + Vector3.Up * .024f, new Vector3(.065f, .047f, .065f), "d4ae48");
    }
    private void ShopsAndHomes()
    {
        // The café arrival: glazed pastry case, baskets and a legible sidewalk menu.
        var p = _map.Point(19.8f, -77.0f);
        _g.Box(p + new Vector3(0, .43f, 0), new Vector3(.8f, .86f, 1.6f), "9c7955");
        for (int j = 0; j < 3; j += 1)
        {
            _g.Box(p + new Vector3(0, .98f, j * .46f - .46f), new Vector3(.76f, .1f, .4f), "ccb486");
            for (int i = 0; i < 4; i += 1)
            {
                _g.Add("sphere", p + new Vector3(-.25f + i * .17f, 1.1f, j * .46f - .46f), new Vector3(.17f, .14f, .23f), new[] { "c6a46d", "d8b679", "a77e4f" }[j]);
            }
        }
        foreach (var z in new[] { -83.0f, -52.0f, -14.0f, 30.0f })
        {
            var at = _map.Point(19.1f, z, .25f);
            _g.Box(at + new Vector3(0, .6f, 0), new Vector3(.17f, 1.2f, .78f), "a18a67");
            _g.Box(at + new Vector3(-.1f, .66f, 0), new Vector3(.04f, .95f, .61f), "365d50");
            _g.Label("TODAY\nCOFFEE\n& WARM\nBREAD", at + new Vector3(-.13f, .66f, 0), .51f, "eadbb8", -Mathf.Pi * .5f, 48);
        }
        // Wall-mounted projecting signs, each with a different painted emblem.
        foreach (var z in new[] { -68.0f, 7.0f })
        {
            foreach (var side in new[] { -1, 1 })
            {
                var at = _map.Point((side == 1 ? 19.8f : -3.8f), z - 4, 3.1f);
                _g.Beam(at, at + new Vector3(-side * 1.1f, 0, 0), .035f, "4a6258");
                _g.Box(at + new Vector3(-side * .7f, -.38f, 0), new Vector3(.75f, .65f, .09f), new[] { "a96b4c", "668470" }[(z < 0 ? 0 : 1)]);
                _g.Label((z < 0 ? "BAKE" : "BOOKS"), at + new Vector3(-side * .7f, -.35f, .06f), .62f, "f0ddb1", 0, 48);
            }
        }
        // Richer residential stoops: door handles, lamps, potted plants and letter boxes.
        for (int row = 0; row < 4; row += 1)
        {
            var z = new[] { -87.0f, -49.0f, -14.0f, 28.0f }[row];
            var yaw = (row % 2 == 0 ? Mathf.Pi : 0f);
            var turn = new Basis(Vector3.Up, yaw);
            for (int side = 0; side < 2; side += 1)
            {
                for (int col = 0; col < 4; col += 1)
                {
                    var x = ((side == 0 ? -59 : 28)) + col * 14;
                    var front = new Vector3(x, 0, z) + turn * new Vector3(0, 0, 8);
                    var o = new Vector3(x, _map.TerrainHeight(front.X, front.Z) + .2f, z);
                    var door = o + turn * new Vector3(3.2f, 1.4f, 6.26f);
                    _g.Add("sphere", door + turn * new Vector3(.46f, 0, 0), new Vector3(.07f, .07f, .07f), "d3b478");
                    _g.Box(o + turn * new Vector3(4.4f, 1.05f, 6.18f), new Vector3(.44f, .55f, .21f), "546f65", false, yaw);
                    _g.Box(o + turn * new Vector3(4.4f, 1.16f, 6.31f), new Vector3(.31f, .035f, .015f), "293e3a", false, yaw);
                    var pot = o + turn * new Vector3(3.9f, .23f, 7.1f);
                    _g.Add("cylinder", pot, new Vector3(.46f, .48f, .46f), "bb8764");
                    _g.Add("leaf", pot + Vector3.Up * .47f, new Vector3(.8f, .9f, .8f), "719147");
                    for (int f = 0; f < 4; f += 1)
                    {
                        Flower(pot + new Vector3(_rng.RandfRange(-.2f, .2f), .8f, _rng.RandfRange(-.2f, .2f)), "c99f7e");
                    }
                    if ((col + row) % 3 == 0)
                    {
                        var at = o + turn * new Vector3(-4.2f, 0, 7.1f);
                        Bicycle(at, yaw, "70919a");
                    }
                    // Recessed roof lanterns and asymmetrical terracotta herb tubs.
                    var floors = (row == 0 || (row * 8 + side * 4 + col) % 4 == 0 ? 3 : 2);
                    var roof = o + Vector3.Up * (floors * 3 + .95f);
                    if (col % 2 == 0)
                    {
                        _g.Box(roof + turn * new Vector3(-2, .0f, -1), new Vector3(2.2f, .26f, 2.8f), "b5aa90", false, yaw);
                        _g.Box(roof + turn * new Vector3(-2, .17f, -1), new Vector3(1.9f, .12f, 2.5f), "6e9699", false, yaw);
                        for (int j = 0; j < 4; j += 1)
                        {
                            _g.Box(roof + turn * new Vector3(-2, .25f, -2 + j * .66f), new Vector3(1.94f, .035f, .035f), "d0c8ab", false, yaw);
                        }
                    }
                }
            }
        }
        // Courts are lush enclosed gardens with stepping stones and climbing trellises.
        foreach (var x in new[] { -40.0f, 52.0f })
        {
            foreach (var z in new[] { -68.0f, 7.0f })
            {
                foreach (var side in new[] { -1, 1 })
                {
                    var at = _map.Point(x + side * 8.4f, z + 1);
                    Bed(at, new Vector2(1.8f, 8), (int)(x + z), false);
                    for (int j = 0; j < 3; j += 1)
                    {
                        var p1 = _map.Point(x + side * 8.0f, z - 3 + j * 3);
                        _g.Add("leaf", p1 + Vector3.Up * .65f, new Vector3(1.4f, 1.65f, 1.4f), "527c46");
                    }
                }
                for (int i = 0; i < 7; i += 1)
                {
                    var at = _map.Point(x - 3.5f + i * .6f, z - 3.5f, .07f);
                    _g.Add("cylinder", at, new Vector3(.45f, .09f, .63f), "b5af94");
                }
            }
        }
    }
    private void Bicycle(Vector3 p, float yaw, string color)
    {
        var turn = new Basis(Vector3.Up, yaw);
        foreach (var x in new[] { -.55f, .55f })
        {
            for (int i = 0; i < 24; i += 1)
            {
                var a = i * Mathf.Tau / 24;
                var b = (i + 1) * Mathf.Tau / 24;
                _g.Beam(p + turn * new Vector3(x + Mathf.Cos(a) * .34f, .37f + Mathf.Sin(a) * .34f, 0), p + turn * new Vector3(x + Mathf.Cos(b) * .34f, .37f + Mathf.Sin(b) * .34f, 0), .025f, "374d48");
            }
            for (int i = 0; i < 8; i += 1)
            {
                var a = i * Mathf.Tau / 8;
                _g.Beam(p + turn * new Vector3(x, .37f, 0), p + turn * new Vector3(x + Mathf.Cos(a) * .32f, .37f + Mathf.Sin(a) * .32f, 0), .005f, "b2b9a5");
            }
        }
        var vertices = new[] { new Vector3(-.55f, .37f, 0), new Vector3(-.18f, .8f, 0), new Vector3(.05f, .36f, 0), new Vector3(.39f, .82f, 0), new Vector3(.55f, .37f, 0) };
        foreach (var edge in new[] { new[] { 0, 1 }, new[] { 1, 2 }, new[] { 2, 0 }, new[] { 1, 3 }, new[] { 3, 2 }, new[] { 3, 4 } })
        {
            _g.Beam(p + turn * vertices[edge[0]], p + turn * vertices[edge[1]], .023f, color);
        }
        _g.Beam(p + turn * new Vector3(.38f, .8f, 0), p + turn * new Vector3(.32f, 1.08f, 0), .02f, "a5afa2");
        _g.Beam(p + turn * new Vector3(.32f, 1.08f, -.18f), p + turn * new Vector3(.32f, 1.08f, .18f), .02f, "52685c");
        _g.Box(p + turn * new Vector3(-.18f, .89f, 0), new Vector3(.28f, .055f, .19f), "635e4c", false, yaw);
        _g.Box(p + turn * new Vector3(.56f, .93f, 0), new Vector3(.27f, .28f, .34f), "b4a27b", false, yaw);
    }
    private void HillsideBorders()
    {
        foreach (var x in new[] { -38.0f, -104.0f })
        {
            for (int z = 48; z < 92; z += 2)
            {
                foreach (var side in new[] { -1, 1 })
                {
                    var y = _map.HeightAt(x, z);
                    var bank = _map.TerrainHeight(x + side * 2.6f, z);
                    var height = Mathf.Max(.45f, bank - y + .15f);
                    _g.Box(new Vector3(x + side * 2.13f, y + height * .5f - .2f, z), new Vector3(.72f, height, 2.04f), "8c957a", false, 0, "brick");
                    var p = _map.Point(x + side * 2.95f, z);
                    _g.Add("leaf", p + Vector3.Up * .35f, new Vector3(1.6f, .9f, 2.3f), new[] { "547944", "769044", "929b50" }[Mathf.PosMod(z, 3)]);
                    if (z % 4 == 0)
                    {
                        Flower(p + Vector3.Up * .85f, "d6a456");
                    }
                }
            }
        }
        // Meadow edges get a continuous transition of shrubs, flowers and rocks.
        foreach (var route in new[] { new[] { new Vector2(-112, 101), new Vector2(-54, 110) }, new[] { new Vector2(-104, 74), new Vector2(-22, 111) }, new[] { new Vector2(-55, 110), new Vector2(-16, 133) } })
        {
            Vector2 a = route[0];
            Vector2 b = route[1];
            var side = (b - a).Normalized().Orthogonal();
            for (int i = 0; i < (int)(a.DistanceTo(b) * 1.4f); i += 1)
            {
                var p = a.Lerp(b, i / (a.DistanceTo(b) * 1.4f));
                foreach (var sign_value in new[] { -1, 1 })
                {
                    var at = p + side * sign_value * _rng.RandfRange(2, 3.5f);
                    if ((Mathf.Abs(at.X + 38) < 3 || Mathf.Abs(at.X + 104) < 3) && at.Y < 96)
                    {
                        continue;
                    }
                    var position = _map.Point(at.X, at.Y);
                    _g.Add("leaf", position + Vector3.Up * .33f, new Vector3(1.35f, .8f, 1.4f), new[] { "748d42", "528044", "8d9747" }[i % 3]);
                    if (i % 2 == 0)
                    {
                        Flower(position + Vector3.Up * .75f, new[] { "dcbb67", "d0c5b9", "be97b0" }[i % 3]);
                    }
                }
            }
        }
        foreach (var x in new[] { -27.0f, -10.0f, 39.0f, 61.0f, 79.0f, 123.0f })
        {
            foreach (var z in new[] { 124.0f, 148.0f, 164.0f })
            {
                Bed(_map.Point(x, z), new Vector2(8, 5), (int)(x + z), false);
            }
        }
        // Pavillion fascia, climbing trellis and planted lower edges make its ramp inviting.
        var pavilion = _map.Point(-56, 62);
        _g.Box(pavilion + new Vector3(0, 1.95f, -3.04f), new Vector3(3.9f, .44f, .09f), "4a705b");
        _g.Label("THE GARDEN ROOM", pavilion + new Vector3(0, 1.95f, -3.1f), 3.5f, "ead9b1", Mathf.Pi);
        foreach (var side in new[] { -1, 1 })
        {
            Bed(pavilion + new Vector3(side * 4.4f, 0, .5f), new Vector2(1.4f, 5.5f), side, false);
            for (int j = 0; j < 8; j += 1)
            {
                _g.Box(pavilion + new Vector3(side * 3.58f, .25f + j * .3f, 0), new Vector3(.08f, .035f, 4.8f), "a6a584");
            }
            for (int j = 0; j < 5; j += 1)
            {
                _g.Box(pavilion + new Vector3(side * 3.59f, 1.3f, -2 + j), new Vector3(.06f, 2.5f, .05f), "a6a584");
            }
            for (int j = 0; j < 12; j += 1)
            {
                _g.Add("leaf", pavilion + new Vector3(side * 3.7f, _rng.RandfRange(.3f, 2.5f), _rng.RandfRange(-2.4f, 2.4f)), new Vector3(.6f, .9f, .75f), "638645");
            }
        }
    }
    private void HarborPlaces()
    {
        // Two shade sails shelter tables without closing the central promenade.
        foreach (var x in new[] { -28.0f, 67.0f })
        {
            var pavilion = _map.Point(x, -114, .14f);
            foreach (var dx in new[] { -3.3f, 3.3f })
            {
                foreach (var dz in new[] { -1.9f, 1.9f })
                {
                    _g.Beam(pavilion + new Vector3(dx, 0, dz), pavilion + new Vector3(dx, 3.2f, dz), .055f, "8c8e70");
                }
            }
            for (int i = 0; i < 10; i += 1)
            {
                _g.Box(pavilion + new Vector3(-3.4f + i * .75f, 3.18f, 0), new Vector3(.12f, .13f, 4.4f), "b5ab84");
            }
            for (int i = 0; i < 6; i += 1)
            {
                _g.Cloth(pavilion + new Vector3(-2.85f + i * 1.14f, 3.12f, -2), new Vector2(1.1f, .32f), "d7c69e");
            }
            foreach (var side in new[] { -1, 1 })
            {
                Bed(pavilion + new Vector3(side * 4.2f, 0, 0), new Vector2(1, 3.6f), (int)(x), true);
            }
        }
        // Rope coils, dock fenders, pier planking and clearly shaped crates.
        for (int z = -160; z < -120; z += 1)
        {
            _g.Box(new Vector3(-114, 2.68f, z + .45f), new Vector3(11.5f, .045f, .035f), "747d6a");
        }
        foreach (var z in new[] { -127.0f, -140.0f, -153.0f })
        {
            foreach (var side in new[] { -1, 1 })
            {
                var pavilion = new Vector3(-114 + side * 5.7f, 2.75f, z);
                _g.Add("cylinder", pavilion + Vector3.Up * .25f, new Vector3(.3f, .5f, .3f), "65796b");
                _g.Beam(pavilion + new Vector3(-.3f, .36f, 0), pavilion + new Vector3(.3f, .36f, 0), .08f, "65796b");
                for (int ring = 0; ring < 4; ring += 1)
                {
                    for (int i = 0; i < 20; i += 1)
                    {
                        var a = i * Mathf.Tau / 20;
                        var b = (i + 1) * Mathf.Tau / 20;
                        var r = .22f + ring * .042f;
                        _g.Beam(pavilion + new Vector3(Mathf.Cos(a) * r, .045f, Mathf.Sin(a) * r + .7f), pavilion + new Vector3(Mathf.Cos(b) * r, .045f, Mathf.Sin(b) * r + .7f), .018f, "b6a078");
                    }
                }
                _g.Add("sphere", pavilion + new Vector3(side * .28f, -1.05f, 0), new Vector3(.42f, 1, .42f), "567167");
            }
        }
        var previous = new Vector3(-119.6f, 3.05f, -142);
        for (int i = 1; i < 17; i += 1)
        {
            var t = i / 16f;
            var next = (new Vector3(-119.6f, 3.05f, -142).Lerp(new Vector3(-123, .45f, -145), t) - Vector3.Up * Mathf.Sin(t * Mathf.Pi) * .4f);
            _g.Beam(previous, next, .02f, "bdab85");
            previous = next;
        }
        for (int i = 0; i < 6; i += 1)
        {
            var pavilion = new Vector3(-111.6f, 2.95f + (i / 3) * .48f, -145 + i % 3 * 1.05f);
            _g.Box(pavilion, new Vector3(.9f, .44f, .85f), "a58c65");
            for (int j = 0; j < 4; j += 1)
            {
                _g.Box(pavilion + new Vector3(-.34f + j * .22f, .24f, 0), new Vector3(.15f, .04f, .85f), "c0a77c");
            }
        }
    }
}
