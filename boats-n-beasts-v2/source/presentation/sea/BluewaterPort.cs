using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

static class BluewaterPort
{
    static readonly Dictionary<(SeaClimate, string), ArrayMesh> cache = [];
    public static MeshInstance3D Make(SeaCountry country)
    {
        var key = (country.Climate, country.Accent);
        if (cache.TryGetValue(key, out var saved)) return new() { Mesh = saved };
        var b = new ActorGeometry();
        Color baseTint = new(country.Shadow), dye = new(country.Accent), oak = new("a96f4c"), gold = new("e9b97d"), cream = new("f7deaf");
        void Post(float x, float z, float h) => b.Tube([new(x, .04f, z), new(x, h, z)], [.065f, .048f], oak);
        void Shed(float width, float length, float height)
        {
            b.RoundBox(new(0, height * .5f, 0), new(width, height, length), .065f, baseTint);
            b.Polygon([new(-width * .60f, height, -length * .59f), new(width * .60f, height, -length * .59f), new(width * .60f, height + .31f, 0), new(-width * .60f, height + .31f, 0)], dye, Vector3.Up);
            b.Polygon([new(-width * .60f, height + .31f, 0), new(width * .60f, height + .31f, 0), new(width * .60f, height, length * .59f), new(-width * .60f, height, length * .59f)], gold, Vector3.Up);
            for (int i = -1; i <= 1; i++)
                b.RoundBox(new(i * width * .29f, height * .54f, -length * .505f), new(.16f, .24f, .03f), .015f, cream);
        }
        if(country.Climate>=SeaClimate.Salt)WalkingScenery.Draw(b,country,port:true);
            else switch (country.Climate)
        {
            case SeaClimate.Cinder:
                Shed(1.38f, 1.03f, .67f);
                for (int k = -1; k <= 1; k += 2)
                {
                    float x = k * .60f;
                    b.Tube([new(x, 0, .81f), new(x, .53f, .81f), new(x, .90f, .81f)], [.40f, .32f, .16f], dye, 9);
                    b.Tube([new(x, .78f, .81f), new(x, 1.32f, .81f)], [.18f, .14f], baseTint, 8);
                    b.Ring(new(x, 1.31f, .81f), .14f, .038f, gold);
                    b.RoundBox(new(x, .23f, .47f), new(.21f, .30f, .06f), .025f, new("f39e54"));
                }
                break;
            case SeaClimate.Delta:
                Shed(1.71f, .76f, .65f);
                for (int k = 0; k < 12; k++)
                {
                    float a = k * Mathf.Tau / 12;
                    var p = new Vector3(.89f, .64f + MathF.Sin(a) * .62f, MathF.Cos(a) * .62f);
                    b.Tube([new(.89f, .64f, 0), p], .043f, gold);
                    b.RoundBox(p, new(.23f, .17f, .16f), .025f, dye);
                }
                break;
            case SeaClimate.Orchard:
                for (int i = -1; i <= 1; i += 2) for (int j = -1; j <= 1; j += 2) Post(i * .66f, j * .40f, 1.0f);
                for (int j = -2; j <= 2; j++)
                {
                    float z = j * .23f;
                    b.Tube([new(-.81f, .96f, z), new(.83f, 1.03f, z)], .062f, oak);
                    b.Sphere(new(-.25f + .36f * MathF.Sin(j * 3), 1.02f, z), new(.71f, .18f, .23f), j % 2 == 0 ? new("659363") : new("8d9c61"));
                    b.Sphere(new(.27f * MathF.Cos(j * 4), .72f, z), new(.13f, .19f, .14f), dye);
                }
                b.RoundBox(new(0, .15f, 0), new(1.48f, .17f, .82f), .035f, oak);
                break;
            case SeaClimate.Shelf:
                b.Sphere(new(0, .16f, 0), new(.92f, .28f, .77f), cream);
                b.Sphere(new(0, .31f, -.13f), new(.63f, .11f, .47f), new("589d9f"));
                b.Ring(new(0, .35f, -.13f), .49f, .068f, new("aacacc"));
                for (int i = 0; i < 3; i++)
                {
                    float x = -.48f + i * .37f;
                    b.Crystal(new(x, .42f, .25f), new(.18f, .46f + i * .14f, .24f), i == 1 ? cream : dye);
                }
                Post(.84f, .19f, .99f);
                b.Polygon([new(.84f, .98f, .19f), new(1.18f, .91f, .18f), new(.84f, .73f, .19f)], new("d45f50"), Vector3.Back);
                break;
            case SeaClimate.Loom:
                Shed(1.34f, .82f, .72f);
                for (int j = 0; j < 4; j++)
                {
                    float a = j * Mathf.Tau / 4 + .48f;
                    var hub = new Vector3(.17f, 1.17f, -.52f);
                    var ray = new Vector3(MathF.Cos(a), MathF.Sin(a), 0);
                    var edge = new Vector3(-ray.Y, ray.X, 0) * .21f;
                    b.Tube([hub, hub + ray * .98f], .043f, oak);
                    b.Polygon([hub + ray * .33f, hub + ray * .95f, hub + ray * .91f + edge, hub + ray * .41f + edge], j % 2 == 0 ? dye : cream, Vector3.Back);
                }
                break;
            case SeaClimate.Choir:
                b.Sphere(new(0, .11f, 0), new(.92f, .23f, .76f), baseTint);
                for (int i = -2; i <= 2; i++)
                {
                    float x = i * .27f, h = .79f + (2 - Math.Abs(i)) * .28f;
                    b.Tube([new(x, .16f, .09f), new(x * .99f, h, .12f), new(x * 1.05f, h + .13f, -.14f)], [.16f, .13f, .18f], dye);
                    b.Sphere(new(x * 1.05f, h + .15f, -.27f), new(.13f, .12f, .042f), baseTint);
                }
                break;
            case SeaClimate.Court:
                b.RoundBox(new(0, .13f, 0), new(1.92f, .23f, 1.28f), .065f, baseTint);
                for (int i = -2; i <= 2; i++)
                    b.Tube([new(i * .34f, .20f, -.44f), new(i * .34f, .90f, -.44f)], [.10f, .086f], cream, 7);
                b.RoundBox(new(0, .59f, .31f), new(1.54f, .74f, .30f), .035f, baseTint);
                b.Polygon([new(-.98f, .98f, -.62f), new(.98f, .98f, -.62f), new(0, 1.42f, -.62f)], dye, Vector3.Back);
                b.RoundBox(new(0, .94f, 0), new(1.89f, .13f, 1.19f), .041f, gold);
                break;
            default:
                b.Sphere(new(0, .22f, 0), new(.68f, .33f, .68f), baseTint);
                for (int plane = 0; plane < 2; plane++)
                {
                    var arc = new Vector3[25];
                    for (int i = 0; i < arc.Length; i++)
                    {
                        float a = i * Mathf.Tau / 24;
                        arc[i] = new(MathF.Cos(a) * .61f, 1 + MathF.Sin(a) * .58f, (plane == 0 ? 1 : -1) * MathF.Cos(a) * .28f);
                    }
                    b.Tube(arc, .043f, gold);
                }
                b.Crystal(new(0, .98f, 0), new(.23f, .39f, .24f), dye);
                break;
        }
        cache[key] = saved = b.Mesh(DioramaSurface.Material);
        return new() { Mesh = saved };
    }
}
