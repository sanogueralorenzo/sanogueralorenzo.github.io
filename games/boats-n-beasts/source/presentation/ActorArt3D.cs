using Godot;
using BoatsNBeasts.Core;
using System;
using System.Collections.Generic;

namespace BoatsNBeasts;

/// <summary>Reusable, code-built tactile actors. One shared mesh/material draw per actor.</summary>
public static partial class ActorArt3D
{
    static readonly Dictionary<string, ArrayMesh> Cache = new();
    public static void ResetCache() => Cache.Clear();
    static Material Material => DioramaSurface.Material;
    static readonly Color Cream = new("ecd8a4"), Wood = new("98633b"), Deck = new("bb8c53"),
        DarkWood = new("694731"), Brass = new("caa467"), Glass = new("284958"),
        Coral = new("cb4829"), Shell = new("cf5531"), DarkCoral = new("9d3224"),
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
            // The visual hull is deliberately larger than its unchanged simulation collider.
            b.Scale(BoatScale);
            Cache[key] = mesh = b.Mesh(Material);
        }
        var root = Instance(mesh, key);
        int starter = Starter(kind);
        if (starter == 0) AddAimedWeapon(root, 0, Math.Max(1, ranks[0]), new(0, .26f, -.325f), 1, "AimPrimary");
        for (int i = 0; i < ranks.Length; i++) if (i != starter && ranks[i] > 0)
        {
            if (i is 0 or 1) AddAimedWeapon(root, i, ranks[i], new(0, .24f, .4f), .69f, "AimSecondary");
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
        // Round stern, broad shoulders and a pointed bow, in actual horizontal coordinates.
        float[] zs = { -.565f, -.46f, -.28f, .12f, .39f, .49f, .52f };
        float[] ws = { .014f, .145f, .245f, .285f, .255f, .19f, .04f };
        for (int i = 1; i < zs.Length; i++) if (z <= zs[i]) return Mathf.Lerp(ws[i - 1], ws[i], (z - zs[i - 1]) / (zs[i] - zs[i - 1]));
        return .04f;
    }

    static Vector3[] HullRing(float y, float scale)
    {
        float[] zs = { -.565f, -.50f, -.40f, -.28f, -.10f, .12f, .30f, .39f, .46f, .50f, .52f };
        var p = new List<Vector3>();
        foreach (float z in zs) p.Add(new(Width(z) * scale, y, z * scale));
        for (int i = zs.Length - 1; i >= 0; i--) p.Add(new(-Width(zs[i]) * scale, y, zs[i] * scale));
        return p.ToArray();
    }

    static void BuildBoat(ActorGeometry b, BoatKind kind, int[] ranks)
    {
        Color stripe = kind == BoatKind.Mage ? new("73539b") : kind == BoatKind.Trawler ? new("358d88") : new("25495d");
        b.Loft(new[] { HullRing(-.055f, .67f), HullRing(.025f, .85f), HullRing(.139f, .987f), HullRing(.205f, 1) }, new[] { DarkWood, stripe, Cream });
        b.Polygon(HullRing(.191f, .935f), Deck, Vector3.Up);
        var rim = HullRing(.218f, .984f);
        b.ClosedTube(rim, .018f, Cream, 7);
        // Wooden inner gunwale gives the hull a visible wall thickness.
        b.ClosedTube(HullRing(.201f, .905f), .012f, DarkWood, 6);
        for (int side = -1; side <= 1; side += 2)
        {
            b.RoundBox(new(side * .215f, .248f, .335f), new(.033f, .095f, .032f), .009f, Wood);
            b.Tube(new[] { new Vector3(side * .225f, .276f, .27f), new Vector3(side * .19f, .276f, .43f) }, .011f, Cream, 7);
            // Side cabin windows sit proud of their cream frame and have roof overhang above.
        }
        b.RoundBox(new(0, .332f, .095f), new(.345f, .273f, .35f), .046f, Cream);
        b.RoundBox(new(0, .461f, .095f), new(.393f, .036f, .406f), .014f, Wood);
        b.RoundBox(new(0, .489f, .095f), new(.419f, .078f, .432f), .036f, new("f5e5be"));
        // Inset dark panes and raised warm frames remain legible at the sailing camera scale.
        b.RoundBox(new(0, .376f, -.085f), new(.254f, .13f, .019f), .008f, Brass);
        b.RoundBox(new(0, .376f, -.097f), new(.228f, .107f, .014f), .006f, Glass);
        b.RoundBox(new(0, .376f, -.107f), new(.016f, .124f, .018f), .005f, Cream);
        foreach (int side in new[] { -1, 1 })
        {
            for (int j = 0; j < 2; j++)
            {
                float z = .015f + .15f * j;
                b.RoundBox(new(side * .173f, .374f, z), new(.018f, .131f, .119f), .007f, Brass);
                b.RoundBox(new(side * .185f, .374f, z), new(.013f, .107f, .095f), .005f, Glass);
                b.RoundBox(new(side * .194f, .40f, z - .025f), new(.004f, .037f, .012f), .0015f, new("72969a"));
            }
            b.RoundBox(new(side * .174f, .29f, .1f), new(.012f, .017f, .26f), .004f, Brass);
        }
        b.RoundBox(new(0, .312f, .278f), new(.131f, .215f, .020f), .009f, Wood);
        b.RoundBox(new(0, .361f, .293f), new(.083f, .083f, .013f), .006f, Glass);
        b.Sphere(new(.036f, .322f, .285f), new(.009f, .009f, .009f), Brass, 8, 5);
        b.RoundBox(new(-.1f, .53f, .18f), new(.066f, .085f, .068f), .012f, DarkWood);
        b.RoundBox(new(-.1f, .578f, .18f), new(.082f, .021f, .084f), .007f, Brass);
        b.Tube(new[] { new Vector3(.11f, .48f, .22f), new Vector3(.11f, .645f, .22f) }, .008f, Wood, 7);
        b.Tube(new[] { new Vector3(.11f, .625f, .22f), new Vector3(.04f, .60f, .22f) }, .008f, Brass, 7);
        int starter = Starter(kind);
        if (starter != 0) Equipment(b, starter, Math.Max(1, ranks[starter]), new(0, .25f, -.34f), starter == 5 ? .95f : 1);
        // One compact stern fitting represents the second weapon slot.
        for (int i = 0; i < ranks.Length; i++) if (i != starter && ranks[i] > 0)
        {
            if (i is not (0 or 1)) Equipment(b, i, ranks[i], new(0, .22f, .405f), .58f);
            break;
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
        Vector3 P(float x, float y, float z) => new Vector3(x, y, z) * s;
        b.Sphere(P(0, .135f, .01f), P(.24f, .135f, .215f), DarkCoral);
        b.Sphere(P(0, .20f, .015f), P(.247f, .13f, .211f), Shell, 20, 12);
        b.Sphere(P(0, .107f, -.15f), P(.185f, .065f, .10f), Coral);
        foreach (int side in new[] { -1, 1 })
        {
            for (int j = 0; j < 3; j++)
            {
                float z = -.005f + j * .095f;
                Vector3 a = P(side * .20f, .14f, z), knee = P(side * (.32f + j * .018f), .11f, z + .06f), end = P(side * (.35f + j * .012f), -.003f, z + .10f);
                b.Tube(new[] { a, knee, end }, new[] { .035f * s, .025f * s, .008f * s }, Coral, 8);
                b.Sphere(knee, P(.028f, .028f, .028f), Shell, 10, 7);
            }
            b.Tube(new[] { P(side * .18f, .13f, -.095f), P(side * .32f, .16f, -.16f), P(side * .35f, .18f, -.26f) }, .036f * s, Coral, 10);
            b.Sphere(P(side * .34f, .192f, -.27f), P(.094f, .077f, .11f), Shell, 14, 9);
            b.Tube(new[] { P(side * .301f, .19f, -.323f), P(side * .285f, .18f, -.418f), P(side * .333f, .175f, -.445f) }, new[] { .044f * s, .027f * s, .006f * s }, Coral, 8);
            b.Tube(new[] { P(side * .388f, .19f, -.319f), P(side * .404f, .18f, -.409f), P(side * .356f, .175f, -.444f) }, new[] { .04f * s, .026f * s, .004f * s }, Shell, 8);
            b.Tube(new[] { P(side * .105f, .228f, -.15f), P(side * .12f, .322f, -.20f) }, .016f * s, DarkCoral, 8);
            b.Sphere(P(side * .12f, .322f, -.204f), P(.050f, .055f, .047f), Eye, 14, 9);
            b.Sphere(P(side * .116f, .347f, -.239f), P(.025f, .027f, .018f), Pupil, 12, 8);
            b.Sphere(P(side * .11f - .006f, .36f, -.252f), P(.006f, .007f, .003f), Eye, 8, 5);
            // Swept brows and a cheek plate give the face intent even at small camera scale.
            b.Tube(new[] { P(side * .07f, .365f, -.217f), P(side * .116f, .378f, -.205f), P(side * .164f, .349f, -.18f) }, new[] { .012f * s, .019f * s, .012f * s }, DarkCoral, 8);
            b.Sphere(P(side * .125f, .20f, -.184f), P(.071f, .035f, .045f), Coral, 12, 7);
            // Small horn and brow connect the eyes to the sculpted shell.
            b.Tube(new[] { P(side * .164f, .255f, -.14f), P(side * .17f, .323f, -.124f) }, new[] { .025f * s, .003f * s }, Coral, 8);
        }
        b.Sphere(P(0, .146f, -.23f), P(.087f, .036f, .018f), DarkWood, 12, 7);
        foreach (int side in new[] { -1, 1 })
            b.Tube(new[] { P(side * .036f, .171f, -.248f), P(side * .031f, .144f, -.251f) }, new[] { .012f * s, .004f * s }, Cream, 7);
        var shellEdge = new Vector3[24];
        for (int i = 0; i < shellEdge.Length; i++)
        {
            float a = i * Mathf.Tau / shellEdge.Length;
            shellEdge[i] = P(MathF.Cos(a) * .24f, .192f, .015f + MathF.Sin(a) * .207f);
        }
        b.ClosedTube(shellEdge, .009f * s, DarkCoral, 6);
        for (int i = 0; i < 5; i++)
        {
            float a = .14f + i * .7f;
            b.Sphere(P(MathF.Cos(a) * .209f, .22f, .015f + MathF.Sin(a) * .175f), P(.04f, .019f, .031f), Coral, 10, 6);
        }
        if (s > 2)
            for (int i=0;i<5;i++)
            {
                float a=.15f+i*Mathf.Pi/4;
                var p=P(Mathf.Cos(a)*.17f,.29f,Mathf.Sin(a)*.15f);
                b.Crystal(p+Vector3.Up*.065f*s,P(.027f,.12f,.027f),Cream);
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
