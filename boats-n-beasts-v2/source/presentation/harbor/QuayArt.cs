using Godot;
using BoatsNBeasts.Core;

namespace BoatsNBeasts;

public static partial class EnvironmentArt3D
{
    internal static Node3D HomePort(HarborLedger ledger)
    {
        var art = new Sculptor();
        const float radius = 5.1f;
        Land(art, radius, 147, false);
        var basePose = art.Transform;
        void Place(Vector3 at, float yaw, float scale, Action prop)
        {
            art.Transform = new Transform3D(Basis.FromEuler(new(0, yaw, 0)).Scaled(Vector3.One * scale), at);
            prop();
            art.Transform = basePose;
        }
        for (int i = 0; i < 9; i++)
        {
            var angle = (i + 1.3f) * .38f;
            var rock = new Vector3(-Mathf.Cos(angle) * 3.25f, .08f, -Mathf.Sin(angle) * 2.58f);
            art.Boulder(rock, new(1.45f, 1.05f + .16f * (i % 3), 1.34f), new("d7946b"), (uint)(28 + i));
        }
        Place(new(-1.60f, .34f, -.85f), -.30f, 1.24f, () => PirateTavern(art));
        Place(new(1.65f, .58f, -2.15f), -.38f, 1.04f, () => Lighthouse(art, .30f));
        Place(new(-2.37f, .19f, 1.43f), -.26f, .94f, () => MarketStall(art));
        if (ledger.Stores > 0)
        {
            Barrel(art, new(-2.95f, .16f, 2.04f), .34f);
            Barrel(art, new(-3.32f, .15f, 1.93f), .28f);
        }
        Palm(art, new(-3.34f,.23f,-1.40f), 2.1f, 67);
        Palm(art, new(.09f,.24f,-2.88f), 2.28f, 52);
        Palm(art, new(3.15f,.16f,-1.44f), 1.72f, 129);
        for (int i = 0; i < 8; i++)
        {
            float t = i / 7f;
            art.RoundedBox(new(.28f + t * .64f, .20f + .045f * i, .18f - t * 2.04f),
                new(.98f, .13f + .09f * i, .36f), .038f, new Color("dfa876").Lightened(.03f * (i % 3)));
        }
        Boatyard(art);
        QuayStones(art);
        Dock(art, 3.92f);
        var carving = new SeedRandom(416);
        for (int plank = 0; plank < 11; plank++)
        {
            float z = 3.92f * (.40f + plank * .095f);
            for (int j = 0; j < 5; j++)
            {
                float x = 1.47f + j * .29f + carving.Range(-.06f,.06f);
                float zz = z + carving.Range(-.13f,.13f);
                art.Face(new(x,.191f,zz),new(x+.09f,.191f,zz+.014f),new(x+carving.Range(.16f,.31f),.191f,zz-.018f),
                    j%2 == 0 ? new("c09b6b") : new("916e50"));
            }
            for (int side = -1; side <= 1; side += 2)
                art.Ellipsoid(new(2.19f + side*.67f,.193f,z),new(.023f,.005f,.023f),new("65524c"),6,3);
        }
        for (int side = -1; side <= 1; side += 2)
        {
            float x = 2.19f + side * .97f;
            for (int span = 0; span < 2; span++)
            {
                float z = 1.88f + span * 1.69f;
                var a = new Vector3(x,.39f,z);
                var b = new Vector3(x,.28f,z+.82f);
                var c = new Vector3(x,.39f,z+1.69f);
                art.Tube(a,b,.019f,.019f,new("bf9b63"),5);
                art.Tube(b,c,.019f,.019f,new("bf9b63"),5);
            }
        }
        Barrel(art,new(2.64f,.205f,4.46f),.28f);
        Barrel(art,new(2.87f,.205f,4.21f),.23f);
        foreach (var (at, size) in new[]{(new Vector3(-3.58f,.11f,1.21f),.42f),(new Vector3(2.99f,.12f,-.87f),.54f),
            (new Vector3(-2.96f,.11f,-.13f),.34f),(new Vector3(.63f,.25f,-2.23f),.50f)})
            Shrub(art,at,size,48);
        Pennants(art, new(2.77f,.19f,.05f),1.58f,.21f);
        Place(new(-.74f,.18f,1.07f), -.21f, 1.0f, () =>
        {
            for (int side = -1; side <= 1; side += 2)
                for (int end = -1; end <= 1; end += 2)
                    art.RoundedBox(new(side * .41f,.27f,end * .22f), new(.082f,.50f,.082f), .012f, new("764c39"));
            art.RoundedBox(new(0,.51f,0), new(1.06f,.12f,.69f), .025f, new("bb774e"));
            art.RoundedBox(new(0,.58f,0), new(.79f,.018f,.51f), .01f, new("ffdfa2"));
            for (int i = 0; i < 3; i++)
                art.Ellipsoid(new(-.23f + i * .21f, .599f, .11f * Mathf.Cos(i * 2)), new(.07f,.012f,.046f), new("549994"), 8, 3);
        });
        MessAwning(art);
        var frame = new Vector3(.32f,.16f,1.22f);
        Place(frame, -.18f, 1, () =>
        {
            Color wood = new("915c3c"), bronze = new("cf8954");
            for (int i = -1; i <= 1; i += 2)
                art.RoundedBox(new(i*.36f,.72f,0),new(.11f,1.43f,.13f),.012f,wood);
            art.RoundedBox(new(0,1.42f,0),new(.94f,.14f,.16f),.02f,wood.Lightened(.20f));
            art.Tube(new(0,1.36f,0), new(0,1.15f,0), .025f,.025f,wood,6);
            if (ledger.HasTongue)
                art.Tube(new(0,1.18f,0), new(0,.85f,0), .027f,.07f,bronze,8);
            if (ledger.BellReleased)
            {
                art.Tube(new(0,1.22f,0), new(0,1.03f,0),.10f,.15f,bronze);
                art.Tube(new(0,1.03f,0), new(0,.89f,0),.15f,.24f,bronze.Lightened(.12f));
                art.Tube(new(0,.89f,0), new(0,.85f,0),.24f,.25f,new("f2bc76"));
            }
        });
        if (ledger.Dedicated)
            for (int i = 0; i < 4; i++) Pennants(art,new(-2.74f+i*1.10f,.20f,2.98f),1.1f,-.08f);
        if (ledger.Dedicated) ReceivingPier(art, ledger.Campaign);
        return art.Finish("LastLightQuay");
    }

    static void QuayStones(Sculptor art)
    {
        var rng = new SeedRandom(715);
        Color[] stones = [new("dbab7b"), new("ecc697"), new("d7a077"), new("e8b584"), new("dbaa83")];
        for (int row = 0; row < 8; row++)
        {
            float z = .11f + row * .36f;
            for (int col = 0; col < 11; col++)
            {
                float x = -3.52f + col * .54f + (row % 2) * .26f;
                if (x * x + z * z > 12.6f || x > .9f && z < 1.13f) continue;
                var at = new Vector3(x, .203f, z);
                art.RoundedBox(at, new(.52f, .065f, .345f), .035f, stones[rng.Index(stones.Length)]);
            }
        }
        for (int i = 0; i < 15; i++)
        {
            float a = -.35f + i*.145f;
            float x = 3.98f * Mathf.Cos(a), z = 3.92f * Mathf.Sin(a);
            if (x > 1.09f && x < 3.3f && z > 2f) continue;
            var pose = art.Transform;
            art.Transform = new Transform3D(Basis.FromEuler(new(0,-a,0)),new(x,0,z));
            art.RoundedBox(new(0,.15f,0),new(.43f,.36f,.60f),.05f,stones[i%stones.Length].Darkened(.15f));
            art.RoundedBox(new(0,.35f,0),new(.49f,.09f,.60f),.04f,stones[(i+2)%stones.Length]);
            art.Transform = pose;
        }
    }
}
