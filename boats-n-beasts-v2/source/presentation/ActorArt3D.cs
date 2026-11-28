using Godot;
using BoatsNBeasts.Core;
using System;
using System.Collections.Generic;

namespace BoatsNBeasts;

/// <summary>One shared mesh/material draw per actor.</summary>
public static partial class ActorArt3D
{
    static readonly Dictionary<string, ArrayMesh> Cache = new();
    public static void ResetCache() => Cache.Clear();
    static Material Material => DioramaSurface.Material;
    static readonly Color Cream = new("f7ddab"), Wood = new("a36a40"), Deck = new("c68c53"),
        DarkWood = new("704429"), Brass = new("d5a664"), Glass = new("284958"),
        Coral = new("e65b3c"), Shell = new("f77b49"), DarkCoral = new("a43434"),
        Eye = new("fff1c7"), Pupil = new("192e31"), Teal = new("438d88"), Purple = new("9358bd");

    public static Node3D Boat(BoatKind kind, int[] weapons)
    {
        var ranks = new int[6];
        for (int i = 0; i < Math.Min(6, weapons.Length); i++) ranks[i] = Math.Clamp(weapons[i], 0, 8);
        string key = $"boat-{kind}-{string.Join('-', ranks)}";
        if (!Cache.TryGetValue(key, out var mesh))
        {
            var b = new ActorGeometry();
            BuildBoat(b, kind, ranks);
            // The visual hull is larger than its simulation collider.
            b.Scale(BoatScale);
            Cache[key] = mesh = b.Mesh(Material);
        }
        var root = Instance(mesh, key);
        if (!Cache.TryGetValue("main-sail", out var sailMesh))
        {
            var sailGeometry = new ActorGeometry(); MainSail(sailGeometry);
            Cache["main-sail"] = sailMesh = sailGeometry.Mesh(Material);
        }
        var sail = new MeshInstance3D { Name = "MainSail", Mesh = sailMesh, Scale = BoatScale * new Vector3(SailWidth, 1, 1),
            CastShadow = GeometryInstance3D.ShadowCastingSetting.On };
        sail.SetInstanceShaderParameter("sail_motion", true);
        sail.SetInstanceShaderParameter("light_through_surface", .72f);
        root.GetChild(0).AddChild(sail);
        int starter = Starter(kind);
        if (starter == 0) AddAimedWeapon(root, 0, Math.Max(1, ranks[0]), new(0, .26f, -.325f), 1, "AimPrimary");
        for (int i = 0; i < ranks.Length; i++) if (i != starter && ranks[i] > 0)
        {
            if (i is 0 or 1) AddAimedWeapon(root, i, ranks[i], SecondaryMount, SecondarySize, "AimSecondary");
            break;
        }
        return root;
    }

    public static Node3D Creature(EnemyKind kind)
    {
        string key = $"creature-{kind}";
        if (!Cache.TryGetValue(key, out var mesh))
        {
            var b = new ActorGeometry();
            switch (kind)
            {
                case EnemyKind.Crab: Crab(b, 1); break;
                case EnemyKind.Leviathan: Crab(b, 2.65f); break;
                case EnemyKind.Puffer: Puffer(b); break;
                case EnemyKind.Serpent: Serpent(b); break;
                case EnemyKind.Ray: Ray(b); break;
            }
            Cache[key] = mesh = b.Mesh(Material);
        }
        return Instance(mesh, key);
    }

    static Node3D Instance(ArrayMesh mesh, string name)
    {
        var root = new Node3D { Name = name };
        root.AddChild(new MeshInstance3D { Name = "Sculpture", Mesh = mesh,
            CastShadow = GeometryInstance3D.ShadowCastingSetting.On });
        return root;
    }

    /// <summary>Only animates the visual child; leaves simulation position and heading untouched.</summary>
    public static void Animate(Node3D root, float clock, float speed)
    {
        if (root.GetChildCount() == 0) return;
        var sculpture = root.GetChild<Node3D>(0);
        bool boat = root.Name.ToString().StartsWith("boat-", StringComparison.Ordinal);
        sculpture.Position = new Vector3(0, MathF.Sin(clock * (boat ? 2.4f : 3.5f)) * .009f, 0);
        sculpture.Rotation = new Vector3(MathF.Sin(clock * 2.1f) * .012f,
            0, MathF.Sin(clock * 2.7f) * (boat ? .018f : .035f));
    }

    static float Width(float z)
    {
        float[] zs = { -.565f, -.46f, -.28f, .12f, .39f, .49f, .52f };
        float[] ws = { .014f, .145f, .245f, .285f, .255f, .19f, .04f };
        for (int i = 1; i < zs.Length; i++) if (z <= zs[i]) return Mathf.Lerp(ws[i - 1], ws[i], (z - zs[i - 1]) / (zs[i] - zs[i - 1]));
        return .04f;
    }

    static Vector3[] HullRing(float y, float scale)
    {
        float[] zs = { -.565f, -.50f, -.40f, -.28f, -.10f, .12f, .30f, .39f, .46f, .50f, .52f };
        var p = new List<Vector3>();
        float Sheer(float z) => .065f * MathF.Pow(MathF.Abs(z) / .565f, 3) * scale;
        foreach (float z in zs) p.Add(new(Width(z) * scale, y + Sheer(z), z * scale));
        for (int i = zs.Length - 1; i >= 0; i--) p.Add(new(-Width(zs[i]) * scale, y + Sheer(zs[i]), zs[i] * scale));
        return p.ToArray();
    }

    static void BuildBoat(ActorGeometry b, BoatKind kind, int[] ranks)
    {
        Color stripe = kind == BoatKind.Mage ? new("73539b") : kind == BoatKind.Trawler ? new("358d88") : new("214f5d");
        b.Loft(new[] { HullRing(-.055f, .67f), HullRing(.025f, .85f), HullRing(.108f, .968f), HullRing(.205f, 1) }, new[] { DarkWood, Wood, stripe });
        b.Polygon(HullRing(.206f, .935f), Deck, Vector3.Up);
        b.ClosedTube(HullRing(.221f, .984f), .017f, Cream, 7);
        b.ClosedTube(HullRing(.125f, .97f), .009f, Brass, 6);
        // Broad planks and open side rails keep the wooden hull legible at playing scale.
        for (int i = -2; i <= 2; i++)
            b.Tube(new[] { new Vector3(i * .073f, .219f, -.25f), new Vector3(i * .073f, .219f, .27f) }, .003f, Wood, 4);
        foreach (int side in new[] { -1, 1 })
        {
            foreach (float z in new[] { -.22f, .03f, .24f })
            {
                float x = side * Width(z) * .97f;
                b.Tube(new[] { new Vector3(x, .22f, z), new Vector3(x, .305f, z) }, .011f, Wood, 6);
                b.RoundBox(new(side * Width(z), .166f, z), new(.014f, .045f, .063f), .005f, DarkWood);
            }
            b.Tube(new[] { new Vector3(side * .22f, .32f, -.28f), new Vector3(side * .275f, .30f, .03f), new Vector3(side * .249f, .33f, .30f) }, .012f, Cream, 6);
        }
        // A short, low quarterdeck leaves a continuous working deck around the mast.
        b.RoundBox(new(0, .263f, .385f), new(.34f, .105f, .17f), .015f, Wood);
        b.RoundBox(new(0, .327f, .385f), new(.38f, .025f, .20f), .010f, Deck);
        b.RoundBox(new(0, .265f, .463f), new(.34f, .106f, .057f), .008f, stripe.Darkened(.25f));
        for (int i = -1; i <= 1; i++)
        {
            b.RoundBox(new(i * .09f, .268f, .497f), new(.061f, .063f, .017f), .005f, Brass);
            b.RoundBox(new(i * .09f, .268f, .508f), new(.036f, .039f, .007f), .003f, Glass);
        }
        foreach (int side in new[] { -1, 1 })
        {
            b.RoundBox(new(side * .174f, .266f, .39f), new(.012f, .046f, .065f), .005f, Brass);
            b.RoundBox(new(side * .182f, .266f, .39f), new(.008f, .028f, .042f), .003f, Glass);
            b.Tube(new[] { new Vector3(side * .18f, .34f, .30f), new Vector3(side * .18f, .405f, .30f),
                new Vector3(side * .18f, .405f, .46f), new Vector3(side * .18f, .34f, .46f) }, .009f, Cream, 6);
        }
        for (int i = 0; i < 2; i++)
            b.RoundBox(new(0, .237f + i * .044f, .23f + i * .035f), new(.13f, .04f, .05f), .004f, Deck);
        BoatCrew(b);
        SternScrolls(b);
        PirateRig(b);
        RamFigurehead(b);
        int starter = Starter(kind);
        if (starter != 0) Equipment(b, starter, Math.Max(1, ranks[starter]), new(0, .25f, -.34f), starter == 5 ? .95f : 1);
        // One compact stern fitting represents the second weapon slot.
        for (int i = 0; i < ranks.Length; i++) if (i != starter && ranks[i] > 0)
        {
            if (i is not (0 or 1)) Equipment(b, i, ranks[i], SecondaryMount, SecondarySize);
            break;
        }
    }

    const float MastHeight = 1.62f, SailWidth = 1.19f;
    public static float BoatHudHeight => (MastHeight + .025f) * BoatScale.Y;

    static void PirateRig(ActorGeometry b)
    {
        b.Tube(new[] { new Vector3(0, .22f, .015f), new Vector3(0, MastHeight, .015f) }, new[] { .024f, .014f }, DarkWood, 8);
        b.Tube(new[] { new Vector3(-.375f * SailWidth, 1.41f, .015f), new Vector3(.375f * SailWidth, 1.41f, .015f) }, .015f, Wood, 8);
        b.Tube(new[] { new Vector3(-.31f * SailWidth, .68f, .015f), new Vector3(.31f * SailWidth, .68f, .015f) }, .011f, Wood, 6);
        foreach (int side in new[] { -1, 1 })
            b.Tube(new[] { new Vector3(0, 1.445f, .015f), new Vector3(side * .255f, .30f, .17f) }, .0045f, DarkWood, 5);
        b.Sphere(new(0, MastHeight, .015f), new(.025f, .025f, .025f), Brass);

        Vector3[] pennant = [new(0, 1.60f, .015f), new(-.12f, 1.58f, .04f), new(-.26f, 1.62f, .02f),
            new(-.20f, 1.56f, .025f), new(-.29f, 1.50f, 0), new(-.12f, 1.47f, .04f), new(0, 1.48f, .015f)];
        b.Polygon(pennant, Coral, Vector3.Back);
    }

    static void MainSail(ActorGeometry b)
    {
        // The middle swells beyond the pinned spar ends, giving the cloth an oval outline.
        float WidthAt(float v) => Mathf.Lerp(.60f, .72f, v) + .16f * Mathf.Sin(v * Mathf.Pi);
        Vector3 Cloth(float u, float v) => new(
            (u - .5f) * WidthAt(v),
            .68f + v * .72f - .025f * MathF.Sin(u * Mathf.Pi) * (1 - v),
            .015f + .30f * MathF.Sin(u * Mathf.Pi) * MathF.Sin(v * Mathf.Pi));
        for (int y = 0; y < 8; y++) for (int x = 0; x < 8; x++)
        {
            var patch = new[] { Cloth(x / 8f, y / 8f), Cloth((x + 1) / 8f, y / 8f),
                Cloth((x + 1) / 8f, (y + 1) / 8f), Cloth(x / 8f, (y + 1) / 8f) };
            Color cloth = x is 0 or 7 ? Cream : new Color("f5e5be");
            b.Polygon(patch, cloth, Vector3.Forward);
        }
    }

    static void SternScrolls(ActorGeometry b)
    {
        // Paired carved scrolls rise from the outside of the stern, leaving the deck clear.
        foreach (int side in new[] { -1, 1 })
        {
            var curl = new List<Vector3> { new(side * .226f, .25f, .35f), new(side * .244f, .34f, .43f) };
            var radii = new List<float> { .027f, .026f };
            for (int i = 0; i <= 20; i++)
            {
                float t = i / 20f, angle = -Mathf.Pi / 2 + t * Mathf.Tau * 1.18f;
                float radius = Mathf.Lerp(.10f, .018f, t);
                curl.Add(new(side * .25f, .52f + Mathf.Sin(angle) * radius, .43f + Mathf.Cos(angle) * radius));
                radii.Add(Mathf.Lerp(.025f, .013f, t));
            }
            b.Tube(curl.ToArray(), radii.ToArray(), Wood, 7);
            var edge = curl.ConvertAll(p => p + new Vector3(side * .020f, .003f, 0));
            b.Tube(edge.ToArray(), .006f, Brass, 5);
        }
    }

    static void RamFigurehead(ActorGeometry b)
    {
        b.Tube(new[] { new Vector3(0, .22f, -.47f), new Vector3(0, .30f, -.61f), new Vector3(0, .39f, -.65f) }, new[] { .045f, .042f, .052f }, Cream, 8);
        b.Sphere(new(0, .415f, -.665f), new(.084f, .075f, .075f), Cream);
        b.Sphere(new(0, .395f, -.727f), new(.065f, .044f, .045f), new("f5e5be"));
        foreach (int side in new[] { -1, 1 })
        {
            b.Sphere(new(side * .07f, .44f, -.635f), new(.044f, .046f, .028f), Brass);
            b.Sphere(new(side * .087f, .441f, -.65f), new(.020f, .025f, .014f), DarkWood);
            b.Sphere(new(side * .091f, .43f, -.657f), new(.016f, .015f, .015f), Cream);
            b.Sphere(new(side * .05f, .431f, -.721f), new(.010f, .012f, .007f), Pupil);
        }
    }

    static void Crystal(ActorGeometry b, Vector3 p, float s)
    {
        b.Sphere(p, new Vector3(.095f, .035f, .087f) * s, DarkWood);
        b.Tube(new[] { p, p + Vector3.Up * .15f * s }, .029f * s, Brass, 8);
        b.Crystal(p + Vector3.Up * .34f * s, new Vector3(.145f, .35f, .125f) * s, Purple);
        b.Ring(p + Vector3.Up * .14f * s, .063f * s, .012f * s, Brass);
    }

    static void Crab(ActorGeometry b, float s)
    {
        Vector3 P(float x, float y, float z) => new Vector3(x * 1.10f, y * 1.13f, z) * s;
        b.Sphere(P(0, .135f, .04f), P(.24f, .135f, .243f), DarkCoral);
        b.Sphere(P(0, .20f, .04f), P(.247f, .13f, .24f), Shell, 20, 12);
        b.Sphere(P(0, .107f, -.15f), P(.185f, .065f, .10f), Coral);
        foreach (int side in new[] { -1, 1 })
        {
            for (int j = 0; j < 3; j++)
            {
                float z = -.06f + j * .116f, fan = (j - 1) * .094f;
                Vector3 a = P(side * .20f, .14f, z), knee = P(side * (.32f + j * .018f), .11f, z + fan * .60f),
                    end = P(side * (.35f + j * .012f), -.003f, z + fan);
                b.Tube(new[] { a, knee, end }, new[] { .035f * s, .025f * s, .008f * s }, Coral, 8);
                b.Sphere(knee, P(.028f, .028f, .028f), Shell, 10, 7);
            }
            b.Tube(new[] { P(side * .105f, .228f, -.15f), P(side * .128f, .332f, -.218f) }, .024f * s, DarkCoral, 8);
            b.Sphere(P(side * .128f, .332f, -.218f), P(.061f, .062f, .048f), Eye, 10, 6);
            b.Sphere(P(side * .146f, .350f, -.254f), P(.032f, .030f, .025f), Pupil, 10, 6);
            b.Sphere(P(side * .151f - .007f, .358f, -.276f), P(.008f, .009f, .006f), Eye, 8, 5);
            b.Tube(new[] { P(side * .073f, .361f, -.252f), P(side * .127f, .387f, -.235f), P(side * .184f, .402f, -.203f) },
                new[] { .013f * s, .020f * s, .009f * s }, DarkCoral, 7);
            b.Sphere(P(side * .125f, .20f, -.184f), P(.071f, .035f, .045f), Coral, 12, 7);
            b.Tube(new[] { P(side * .164f, .255f, -.14f), P(side * .17f, .323f, -.124f) }, new[] { .025f * s, .003f * s }, Coral, 8);
        }
        Claw(-1, .387f, -.385f, -.82f, 1);
        Claw(1, .324f, .027f, -1.05f, .90f);
        b.Sphere(P(0, .146f, -.23f), P(.087f, .036f, .018f), Pupil, 10, 6);
        foreach (int side in new[] { -1, 1 })
            b.Tube(new[] { P(side * .036f, .171f, -.248f), P(side * .031f, .144f, -.251f) }, new[] { .012f * s, .004f * s }, Cream, 7);
        var shellEdge = new Vector3[24];
        for (int i = 0; i < shellEdge.Length; i++)
        {
            float a = i * Mathf.Tau / shellEdge.Length;
            shellEdge[i] = P(MathF.Cos(a) * .24f, .192f, .04f + MathF.Sin(a) * .237f);
        }
        b.ClosedTube(shellEdge, .009f * s, DarkCoral, 6);
        for (int i = 0; i < 5; i++)
        {
            float a = .14f + i * .7f;
            b.Sphere(P(MathF.Cos(a) * .209f, .22f, .04f + MathF.Sin(a) * .199f), P(.04f, .019f, .031f), Coral, 10, 6);
        }
        if (s > 2)
            for (int i=0;i<5;i++)
            {
                float a=.15f+i*Mathf.Pi/4;
                var p=P(Mathf.Cos(a)*.17f,.29f,Mathf.Sin(a)*.15f);
                b.Crystal(p+Vector3.Up*.065f*s,P(.027f,.12f,.027f),Cream);
            }

        void Claw(int side, float height, float reach, float sweep, float size)
        {
            var center = new Vector3(side * .451f, height, reach);
            var across = new Vector3(side, 0, sweep).Normalized();
            var facing = new Vector3(side * sweep, 0, -1).Normalized();
            Vector3 Point(Vector2 point, float depth)
            {
                Vector3 q = center + size * (across * point.X + Vector3.Up * point.Y + facing * depth);
                return P(q.X, q.Y, q.Z);
            }

            b.Tube([P(side * .18f, .13f, -.095f), P(side * .34f, .18f, Mathf.Lerp(-.095f, reach, .57f)),
                Point(new(-.038f, -.064f), 0)], [.054f * s, .045f * s, .045f * s], Coral, 7);
            Plate([new(-.12f, -.10f), new(.025f, -.13f), new(.137f, -.075f), new(.158f, .032f),
                new(.091f, .128f), new(-.074f, .135f), new(-.157f, .053f)], Vector2.Zero, .117f, Coral);
            Plate([new(.003f, -.027f), new(.117f, -.026f), new(.204f, .064f), new(.243f, .171f), new(.227f, .281f),
                new(.128f, .385f), new(.145f, .275f), new(.121f, .195f), new(.06f, .12f)], new(.178f, .173f), .101f, Shell);
            Plate([new(-.096f, -.034f), new(-.032f, -.017f), new(.014f, .052f), new(-.014f, .115f),
                new(-.057f, .193f), new(-.153f, .267f), new(-.166f, .166f), new(-.133f, .069f)], new(-.094f, .091f), .083f, Shell);

            void Plate(Vector2[] outline, Vector2 ridge, float depth, Color color)
            {
                Vector3 front = Point(ridge, depth), back = Point(ridge, -depth);
                Color frontBevel = color.Darkened(.08f), backFace = color.Darkened(.14f), backBevel = color.Darkened(.22f);
                for (int i = 0; i < outline.Length; i++)
                {
                    Vector2 start = outline[i], end = outline[(i + 1) % outline.Length];
                    Vector2 insetStart = ridge.Lerp(start, .77f), insetEnd = ridge.Lerp(end, .77f);
                    Vector3 edgeStart = Point(start, 0), edgeEnd = Point(end, 0);
                    Vector3 frontStart = Point(insetStart, depth * .76f), frontEnd = Point(insetEnd, depth * .76f);
                    Vector3 backStart = Point(insetStart, -depth * .76f), backEnd = Point(insetEnd, -depth * .76f);
                    b.Polygon([front, frontStart, frontEnd], color, facing);
                    b.Polygon([frontStart, edgeStart, edgeEnd, frontEnd], frontBevel, facing);
                    b.Polygon([back, backStart, backEnd], backFace, -facing);
                    b.Polygon([backStart, edgeStart, edgeEnd, backEnd], backBevel, -facing);
                }
            }
        }
    }

    static void Puffer(ActorGeometry b)
    {
        Color gold = new("cfa65d");
        b.Sphere(new(0, .18f, 0), new(.265f, .235f, .25f), gold, 20, 12);
        b.Sphere(new(0, .10f, -.11f), new(.205f, .135f, .17f), Cream);
        for (int j = 0; j < 12; j++)
        {
            float y = .15f + .8f * (j + .5f) / 12, a = j * 2.39996f;
            var n = new Vector3(MathF.Sqrt(1 - y * y) * MathF.Cos(a), y, MathF.Sqrt(1 - y * y) * MathF.Sin(a));
            var p = new Vector3(0, .18f, 0) + n * new Vector3(.25f, .22f, .24f);
            b.Tube(new[] { p, p + n * .066f }, new[] { .025f, .002f }, Cream, 7);
        }
        foreach (int side in new[] { -1, 1 })
        {
            b.Sphere(new(side * .25f, .14f, .035f), new(.105f, .033f, .08f), new("b5864c"));
            Eyes(b, new(side * .11f, .245f, -.207f), .055f);
        }
        b.Sphere(new(0, .165f, -.275f), new(.045f, .036f, .023f), DarkWood);
        b.Sphere(new(0, .185f, .27f), new(.12f, .028f, .105f), gold);
    }

    static void Serpent(ActorGeometry b)
    {
        Color skin=new("3ca99c"), fin=new("ed8057");
        var path=new[] { new Vector3(.04f,-.025f,.90f),new Vector3(-.08f,.04f,.65f),new Vector3(-.12f,.12f,.40f),new Vector3(-.06f,.20f,.16f),new Vector3(0,.17f,-.08f),new Vector3(0,.13f,-.30f) };
        b.Tube(path,new[] { .014f,.055f,.09f,.12f,.16f,.17f },skin,8);
        b.Sphere(new(0,.14f,-.33f),new(.18f,.145f,.24f),skin,10,6);
        b.Sphere(new(0,.07f,-.40f),new(.14f,.04f,.17f),Cream,8,4);
        foreach(int side in new[] {-1,1})
        {
            Eyes(b,new(side*.126f,.245f,-.425f),.05f);
            b.Crystal(new(side*.16f,.09f,-.07f),new(.095f,.055f,.09f),fin);
        }
        for(int i=1;i<path.Length-1;i++)
            b.Crystal(path[i]+Vector3.Up*.09f,new(.04f,.09f,.055f),fin);
    }

    static void Ray(ActorGeometry b)
    {
        Color skin = new("677a91"), edge = new("96a3ae");
        b.Sphere(new(0, .068f, 0), new(.19f, .098f, .29f), skin);
        foreach (int side in new[] { -1, 1 })
        {
            b.Loft(new[] {
                new[] { new Vector3(side*.10f,.10f,-.23f), new Vector3(side*.39f,.025f,.05f), new Vector3(side*.24f,.035f,.22f), new Vector3(side*.10f,.10f,.18f) },
                new[] { new Vector3(side*.10f,.044f,-.23f), new Vector3(side*.39f,.009f,.05f), new Vector3(side*.24f,.015f,.22f), new Vector3(side*.10f,.044f,.18f) }
            }, new[] { edge });
            b.Polygon(new[] { new Vector3(side*.10f,.10f,-.23f), new Vector3(side*.39f,.025f,.05f), new Vector3(side*.24f,.035f,.22f), new Vector3(side*.10f,.10f,.18f) }, skin, Vector3.Up);
            Eyes(b, new(side * .071f, .143f, -.17f), .034f);
        }
        b.Tube(new[] { new Vector3(0, .05f, .2f), new Vector3(.035f, .025f, .42f), new Vector3(.11f, .06f, .62f) }, new[] { .041f, .018f, .002f }, skin, 10);
    }

    static void Eyes(ActorGeometry b, Vector3 p, float r)
    {
        b.Sphere(p, new(r, r * 1.1f, r * .85f), Eye, 12, 8);
        b.Sphere(p + new Vector3(0, .002f, -r * .72f), new(r * .47f, r * .59f, r * .22f), Pupil, 12, 8);
        b.Sphere(p + new Vector3(-r * .13f, r * .23f, -r * .92f), Vector3.One * r * .12f, Eye, 8, 5);
    }
}
