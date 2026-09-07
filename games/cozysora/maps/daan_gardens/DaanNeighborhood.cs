using Godot;

namespace CozySora;

public sealed class DaanNeighborhood
{
    private DaanWorld _map = null!;
    private DaanGeometry _g = null!;
    private readonly RandomNumberGenerator _rng = new();
    private Vector3 _origin;
    private readonly Basis _turn = new(Vector3.Up, -Mathf.Pi * .5f);
    public void Build(DaanWorld world, DaanGeometry geometry)
    {
        _map = world;
        _g = geometry;
        _rng.Seed = 80526;
        string[] names = ["MORNING TEA", "LEAF & CUP", "PARK BOOKS", "AFTER RAIN", "LITTLE BAKERY", "SUMMER TABLE", "GREEN CORNER", "SLOW AFTERNOON"];
        for (int i = 0; i < 8; i += 1)
        {
            Building(new Vector3(108 + (i % 3) * .35f, 1.2f, -81 + i * 23), 12f + i % 3, 3 + i % 3, i, names[i]);
        }
        for (int cluster = 0; cluster < 5; cluster += 1)
        {
            var z = -88f + cluster * 38;
            for (int i = 0; i < (cluster % 2 == 0 ? 3 : 2); i += 1)
            {
                Scooter(new Vector3(92.3f + (i % 2) * .2f, 1.27f, z + i * 1.4f), -.18f + i * .14f, cluster + i);
            }
            _g.Box(new Vector3(92.3f, 1.28f, z + 1.4f), new Vector3(.08f, .012f, 6.2f), "b9b991");
        }
        for (int i = 0; i < 7; i += 1)
        {
            ServiceCourt(new Vector3(108, 1.2f, -69.5f + i * 23), i);
        }
        foreach (var z in new[] { -90f, -38f, 8f, 57f, 94f })
        {
            _g.Add("cylinder", new Vector3(79, 3.2f, z), new Vector3(.13f, 4, .13f), "6f8278", Vector3.Zero, true);
            _g.Beam(new Vector3(79, 5.1f, z), new Vector3(81, 5.1f, z), .055f, "6f8278");
            _g.Box(new Vector3(81, 5.03f, z), new Vector3(.8f, .13f, .32f), "c7c8ab");
        }
        // Back alleys and pale distant buildings anchor the park inside an inhabited city.
        _g.Box(new Vector3(120, 1.21f, 0), new Vector3(8, .025f, 237), "8f9487");
        _g.Box(new Vector3(15, 1.17f, -129), new Vector3(290, .05f, 15), "89978c");
        _g.Box(new Vector3(15, 1.17f, 128), new Vector3(290, .05f, 15), "89978c");
        for (int i = 0; i < 32; i += 1)
        {
            var x = 143f + (i % 3) * 15f;
            var z = -161f + i * 10.5f;
            var h = _rng.RandfRange(13, 35);
            SkyBuilding(new Vector3(x, 1.2f, z), new Vector3(12, h, 13), i);
        }
        for (int i = 0; i < 20; i += 1)
        {
            var x = -144f + i * 15;
            SkyBuilding(new Vector3(x, 1.2f, -153 - _rng.RandfRange(0, 20)), new Vector3(11, _rng.RandfRange(15, 29), 13), i);
            SkyBuilding(new Vector3(x, 1.2f, 153 + _rng.RandfRange(0, 20)), new Vector3(12, _rng.RandfRange(15, 27), 12), i + 2);
        }
    }
    private Vector3 At(Vector3 p)
    {
        return _origin + _turn * p;
    }
    private void Box(Vector3 p, Vector3 size, string color, bool solid = false, int finish = 0)
    {
        _g.Box(At(p), size, color, solid, -Mathf.Pi * .5f, finish);
    }
    private void Building(Vector3 p, float w, int floors, int index, string title)
    {
        _origin = p;
        var tile = new[] { "b2baa5", "b4a794", "9eafa5", "b5b89f" }[index % 4];
        var accent = new[] { "698574", "8c8270", "6f8790", "8e986e" }[index % 4];
        var h = 3.5f + floors * 2.8f;
        // Side and rear walls leave the recessed ground floor and central café door accessible.
        Box(new Vector3(0, h * .5f, -5.8f), new Vector3(w, h, .35f), tile, true, 2);
        foreach (var side in new[] { -1, 1 })
        {
            Box(new Vector3(side * (w * .5f - .14f), h * .5f, 0), new Vector3(.28f, h, 12), tile, true, 2);
        }
        Box(new Vector3(0, (h + 3.3f) * .5f, 0), new Vector3(w, h - 3.3f, 12), tile, true, 2);
        Box(new Vector3(0, .025f, 0), new Vector3(w, .05f, 12), "b2ae96", false, 1);
        Box(new Vector3(0, 3.25f, 0), new Vector3(w, .16f, 12.2f), "b6bba7", true);
        foreach (var x in new[] { -w * .5f + 1.5f, w * .5f - 1.5f })
        {
            Box(new Vector3(x, 1.5f, 5.87f), new Vector3(2.8f, 2.7f, .08f), "506e69", true);
            foreach (var dx in new[] { -1.4f, 0, 1.4f })
            {
                Box(new Vector3(x + dx, 1.5f, 5.96f), new Vector3(.07f, 2.8f, .06f), "c4c7b0");
            }
            Box(new Vector3(x, 1.48f, 5.96f), new Vector3(2.8f, .065f, .06f), "c4c7b0");
        }
        foreach (var side in new[] { -1, 1 })
        {
            Box(new Vector3(side * 1.35f, 1.4f, 5.95f), new Vector3(.14f, 2.8f, .16f), accent, true);
        }
        Box(new Vector3(0, 2.85f, 5.93f), new Vector3(2.8f, .14f, .18f), accent, true);
        Box(new Vector3(0, .025f, 7.5f), new Vector3(w, .05f, 3.3f), "b2ae96", false, 1);
        foreach (var x in new[] { -3.7f, 3.7f })
        {
            Table(new Vector3(x, 0, 2.0f));
            Box(new Vector3(x, 2.85f, 1.5f), new Vector3(.035f, .6f, .035f), "73877a");
            _g.Add("cylinder", At(new Vector3(x, 2.49f, 1.5f)), new Vector3(.62f, .16f, .62f), "d3bd91");
        }
        // Interior fixtures remain visible through the open doorway.
        Box(new Vector3(0, .48f, -2.9f), new Vector3(5, .96f, 1.1f), "9b8d6c", true, 3);
        Box(new Vector3(0, 1.0f, -2.9f), new Vector3(5.2f, .09f, 1.25f), "cec3a0");
        foreach (var x in new[] { -1.5f, 0, 1.5f })
        {
            _g.Add("cylinder", At(new Vector3(x, 1.15f, -2.8f)), new Vector3(.16f, .2f, .16f), "ded8ba");
        }
        foreach (var y in new[] { 1.1f, 1.8f, 2.5f })
        {
            Box(new Vector3(0, y, -5.35f), new Vector3(7, .1f, .65f), accent);
            for (int j = 0; j < 15; j += 1)
            {
                Box(new Vector3(-3.2f + j * .45f, y + .21f, -5.25f), new Vector3(.19f, .33f, .24f), new[] { "d4bc87", "9ead8b", "b78f75", "839999" }[j % 4]);
            }
        }
        Box(new Vector3(0, 3.05f, 6.14f), new Vector3(w - .3f, .48f, .18f), accent);
        _g.Label(title, At(new Vector3(0, 3.08f, 6.25f)), w - 1, "ece1bc", -Mathf.Pi * .5f);
        // A striped fabric canopy slopes away from the shop front.
        for (int stripe = 0; stripe < (int)(w / .35f); stripe += 1)
        {
            var x = -w * .5f + .175f + stripe * .35f;
            _g.Add("box", At(new Vector3(x, 2.77f, 7.0f)), new Vector3(.35f, .045f, 1.85f), (stripe % 2 == 0 ? accent : "d8d0af"), new Vector3(.13f, -Mathf.Pi * .5f, 0));
            Box(new Vector3(x, 2.63f, 7.92f), new Vector3(.35f, .2f, .04f), (stripe % 2 == 0 ? accent : "d8d0af"));
        }
        foreach (var x in new[] { -w * .5f + .3f, w * .5f - .3f })
        {
            _g.Beam(At(new Vector3(x, 2.1f, 6.1f)), At(new Vector3(x, 2.65f, 7.8f)), .025f, accent);
        }
        // Balcony slabs, barred windows, AC boxes and hanging plants vary per apartment.
        for (int floor = 0; floor < floors; floor += 1)
        {
            var y = 4.65f + floor * 2.8f;
            for (int bay = 0; bay < 3; bay += 1)
            {
                var x = (bay - 1) * (w / 3f);
                Box(new Vector3(x, y, 6.015f), new Vector3(2.4f, 1.7f, .055f), "527471");
                foreach (var dx in new[] { -1.25f, 0, 1.25f })
                {
                    Box(new Vector3(x + dx, y, 6.065f), new Vector3(.07f, 1.85f, .085f), "c5c9b4");
                }
                foreach (var dy in new[] { -.92f, 0, .92f })
                {
                    Box(new Vector3(x, y + dy, 6.07f), new Vector3(2.58f, .06f, .09f), "c5c9b4");
                }
                if ((floor + bay + index) % 3 != 0)
                {
                    Box(new Vector3(x, y - .94f, 6.52f), new Vector3(3.0f, .13f, 1.2f), accent, true);
                    for (int j = 0; j < 9; j += 1)
                    {
                        Box(new Vector3(x - 1.4f + j * .35f, y - .43f, 7.08f), new Vector3(.035f, 1, .035f), "a6b6a4");
                    }
                    foreach (var level in new[] { y - .91f, y + .09f })
                    {
                        Box(new Vector3(x, level, 7.08f), new Vector3(2.9f, .045f, .045f), "adb9a5");
                    }
                    foreach (var side in new[] { -1, 1 })
                    {
                        Box(new Vector3(x + side * 1.43f, y - .43f, 6.53f), new Vector3(.035f, 1, 1.1f), "a6b6a4");
                    }
                    Planter(new Vector3(x + .7f, y - .66f, 6.6f), .65f);
                }
                else
                {
                    for (int j = 0; j < 7; j += 1)
                    {
                        Box(new Vector3(x - 1.1f + j * .37f, y, 6.16f), new Vector3(.025f, 1.75f, .04f), "92a591");
                    }
                    Box(new Vector3(x, y - .57f, 6.19f), new Vector3(2.5f, .03f, .04f), "92a591");
                }
                Box(new Vector3(x + 1.48f, y + .1f, 6.23f), new Vector3(.48f, .56f, .43f), "c2c2aa");
                for (int j = 0; j < 4; j += 1)
                {
                    Box(new Vector3(x + 1.48f, y - .07f + j * .1f, 6.46f), new Vector3(.36f, .025f, .025f), "8d9d90");
                }
            }
        }
        // Both side elevations have small windows and rain streaks, visible from the side courts.
        foreach (var side in new[] { -1, 1 })
        {
            for (int floor = 0; floor < floors; floor += 1)
            {
                var y = 4.65f + floor * 2.8f;
                foreach (var z in new[] { -3.5f, .0f, 3.5f })
                {
                    Box(new Vector3(side * (w * .5f + .03f), y, z), new Vector3(.07f, 1.4f, 1.6f), "628077");
                    foreach (var dz in new[] { -.85f, 0, .85f })
                    {
                        Box(new Vector3(side * (w * .5f + .08f), y, z + dz), new Vector3(.06f, 1.5f, .05f), "b9c2a9");
                    }
                    foreach (var dy in new[] { -.76f, .76f })
                    {
                        Box(new Vector3(side * (w * .5f + .08f), y + dy, z), new Vector3(.06f, .055f, 1.75f), "b9c2a9");
                    }
                }
            }
        }
        // Usable flat roof, parapets, a water tank and utility pipework.
        Box(new Vector3(0, h + .08f, 0), new Vector3(w + .15f, .16f, 12.2f), "a2ac97", true);
        foreach (var z in new[] { -5.9f, 5.9f })
        {
            Box(new Vector3(0, h + .5f, z), new Vector3(w, .85f, .17f), tile, true, 2);
        }
        foreach (var x in new[] { -w * .5f, w * .5f })
        {
            Box(new Vector3(x, h + .5f, 0), new Vector3(.17f, .85f, 12), tile, true, 2);
        }
        Box(new Vector3(-2, h + .33f, -2), new Vector3(2.3f, .5f, 2.3f), accent, true);
        _g.Add("cylinder", At(new Vector3(-2, h + 1.6f, -2)), new Vector3(1.9f, 2.1f, 1.9f), "bfc5b2", Vector3.Zero, true);
        foreach (var y in new[] { h + .67f, h + 1.5f, h + 2.5f })
        {
            _g.Add("cylinder", At(new Vector3(-2, y, -2)), new Vector3(1.98f, .065f, 1.98f), "8d9f94");
        }
        _g.Beam(At(new Vector3(-.9f, h + .25f, -2)), At(new Vector3(-.9f, h + 1.5f, -2)), .06f, "81988d");
        for (int k = 0; k < 4; k += 1)
        {
            Planter(new Vector3(2 + k * .65f, h + .32f, 3.6f), .5f);
        }
        // Two café tables outside flank a generous clear route to the doorway.
        foreach (var x in new[] { -3.4f, 3.4f })
        {
            Table(new Vector3(x, 0, 8.3f));
            Planter(new Vector3(x * .48f, .32f, 6.7f), .7f);
        }
        Box(new Vector3(-w * .5f - .25f, 2.15f, 6.25f), new Vector3(.55f, 2.2f, .3f), accent);
        _g.Label("TEA\n&\nCOFFEE", At(new Vector3(-w * .5f - .25f, 2.2f, 6.42f)), .44f, "e4dab9", -Mathf.Pi * .5f);
        // Rainwater pipe and a wall-mounted meter create detail at cat height.
        _g.Beam(At(new Vector3(w * .5f - .35f, .15f, 6.1f)), At(new Vector3(w * .5f - .35f, h - .5f, 6.1f)), .06f, "8d9e8b");
        Box(new Vector3(w * .5f - .64f, 1.25f, 6.13f), new Vector3(.34f, .5f, .15f), "8a9f91");
    }
    private void Planter(Vector3 p, float s)
    {
        _g.Add("cylinder", At(p), new Vector3(s, .55f, s), "a29475");
        for (int j = 0; j < 6; j += 1)
        {
            var a = j * 2.399f;
            _g.Add("sphere", At(p + new Vector3(Mathf.Cos(a) * s * .3f, .43f + Mathf.Sin(j) * .09f, Mathf.Sin(a) * s * .3f)), new Vector3(s * .5f, .5f, s * .4f), "7c9461");
        }
    }
    private void Table(Vector3 p)
    {
        _g.Add("cylinder", At(p + new Vector3(0, .38f, 0)), new Vector3(.15f, .76f, .15f), "6d8373");
        _g.Add("cylinder", At(p + new Vector3(0, .78f, 0)), new Vector3(.9f, .08f, .9f), "b6a680", Vector3.Zero, true);
        _g.Add("cylinder", At(p + new Vector3(0, .88f, 0)), new Vector3(.13f, .15f, .13f), "e3dcc1");
        foreach (var x in new[] { -.7f, .7f })
        {
            Box(p + new Vector3(x, .45f, 0), new Vector3(.4f, .07f, .4f), "8e9b79", true);
            foreach (var dx in new[] { -.16f, .16f })
            {
                foreach (var dz in new[] { -.16f, .16f })
                {
                    Box(p + new Vector3(x + dx, .23f, dz), new Vector3(.04f, .46f, .04f), "657c6d");
                }
            }
            Box(p + new Vector3(x, .72f, -.18f), new Vector3(.42f, .42f, .05f), "8e9b79");
        }
    }
    private void Scooter(Vector3 p, float yaw, int index)
    {
        var basis = new Basis(Vector3.Up, yaw);
        foreach (var z in new[] { -.48f, .48f })
        {
            _g.Add("cylinder", p + basis * new Vector3(0, .25f, z), new Vector3(.48f, .13f, .48f), "414e48", new Vector3(0, yaw, Mathf.Pi * .5f));
            _g.Add("cylinder", p + basis * new Vector3(0, .25f, z), new Vector3(.26f, .15f, .26f), "98a797", new Vector3(0, yaw, Mathf.Pi * .5f));
        }
        var color = new[] { "929f85", "b3987e", "839ea0", "c2bd99" }[index % 4];
        _g.Box(p + basis * new Vector3(0, .46f, .05f), new Vector3(.48f, .35f, .95f), color, true, yaw);
        _g.Box(p + basis * new Vector3(0, .7f, -.16f), new Vector3(.45f, .11f, .62f), "59655b", false, yaw);
        _g.Box(p + basis * new Vector3(0, .71f, .42f), new Vector3(.48f, .56f, .17f), color, false, yaw);
        _g.Beam(p + basis * new Vector3(-.33f, 1, .41f), p + basis * new Vector3(.33f, 1, .41f), .035f, "697c6e");
        _g.Box(p + basis * new Vector3(0, .87f, .52f), new Vector3(.2f, .15f, .03f), "e2d9b3", false, yaw);
        foreach (var side in new[] { -1, 1 })
        {
            _g.Beam(p + basis * new Vector3(side * .25f, 1, .4f), p + basis * new Vector3(side * .34f, 1.22f, .42f), .012f, "829689");
            _g.Add("sphere", p + basis * new Vector3(side * .34f, 1.24f, .42f), new Vector3(.15f, .09f, .04f), "aec0af", new Vector3(0, yaw, 0));
        }
    }
    private void SkyBuilding(Vector3 p, Vector3 size, int index)
    {
        var color = new[] { "9bac9d", "aeb7a1", "93a89e" }[index % 3];
        _g.Box(p + new Vector3(0, size.Y * .5f, 0), size, color);
        _g.Box(p + new Vector3(0, size.Y + .4f, 0), new Vector3(size.X + .3f, .5f, size.Z + .3f), color);
        for (int y = 3; y < (int)(size.Y) - 1; y += 3)
        {
            foreach (var z in new[] { -size.Z * .5f - .025f, size.Z * .5f + .025f })
            {
                for (int x = -4; x < 5; x += 3)
                {
                    _g.Box(p + new Vector3(x, y, z), new Vector3(1.4f, 1.4f, .05f), "7e9b91");
                }
            }
            for (int z = -4; z < 5; z += 3)
            {
                _g.Box(p + new Vector3(-size.X * .5f - .025f, y, z), new Vector3(.05f, 1.4f, 1.5f), "7e9b91");
            }
        }
    }
    private void ServiceCourt(Vector3 p, int index)
    {
        // A side passage meets the café sidewalk and leads to a shared bicycle courtyard.
        _origin = p;
        Box(new Vector3(0, .02f, 1), new Vector3(7, .04f, 11), "a6ad96", false, 1);
        Box(new Vector3(0, 1.0f, -3.6f), new Vector3(7, 2, .18f), "8e9e85", true, 2);
        foreach (var x in new[] { -2.3f, 0, 2.3f })
        {
            Box(new Vector3(x, 1.2f, 3.6f), new Vector3(.11f, 2.4f, .11f), "7f9378", true);
        }
        foreach (var z in new[] { -1f, 1f, 3f, 4.8f })
        {
            Box(new Vector3(0, 2.4f, z), new Vector3(7, .09f, .11f), "8a987a");
        }
        foreach (var x in new[] { -3f, -1.5f, 0, 1.5f, 3f })
        {
            Box(new Vector3(x, 2.42f, 1.8f), new Vector3(.1f, .1f, 6.4f), "8a987a");
        }
        foreach (var x in new[] { -2.8f, 2.8f })
        {
            Planter(new Vector3(x, .4f, 4.8f), 1.1f);
            Box(new Vector3(x, .4f, -2.4f), new Vector3(1.6f, .8f, .65f), "9d9d7d", true);
        }
        for (int i = 0; i < 4; i += 1)
        {
            var x = -2.2f + i * 1.45f;
            _g.Beam(At(new Vector3(x, 0, -.5f)), At(new Vector3(x, .6f, -.5f)), .03f, "6e8877");
            _g.Beam(At(new Vector3(x, .6f, -.5f)), At(new Vector3(x, .6f, -1.5f)), .03f, "6e8877");
            _g.Beam(At(new Vector3(x, .6f, -1.5f)), At(new Vector3(x, 0, -1.5f)), .03f, "6e8877");
        }
        // A chalkboard and a pair of stacked crates sit beside, rather than in, the passage.
        Box(new Vector3(2.4f, .62f, 6.6f), new Vector3(.72f, 1.24f, .1f), "63816b", true);
        _g.Label("TEA\n& A LITTLE\nTIME", At(new Vector3(2.4f, .73f, 6.67f)), .58f, "ddd5ae", -Mathf.Pi * .5f);
        for (int i = 0; i < 2; i += 1)
        {
            Box(new Vector3(-2.5f, .2f + i * .38f, 6.5f), new Vector3(.75f, .36f, .6f), "a99a74", true, 3);
        }
    }
}
