using Godot;
using BoatsNBeasts.Core;
using System;
using System.Collections.Generic;

namespace BoatsNBeasts;

/// <summary>Reusable, code-built tactile actors. One shared mesh/material draw per actor.</summary>
public static class ActorArt3D
{
    static readonly Dictionary<string, ArrayMesh> Cache = new();
    static readonly StandardMaterial3D Material = new()
    {
        VertexColorUseAsAlbedo = true, Roughness = .88f, Metallic = 0,
        CullMode = BaseMaterial3D.CullModeEnum.Back
    };
    static readonly Color Cream = new("ecd8a4"), Wood = new("98633b"), Deck = new("bb8c53"),
        DarkWood = new("694731"), Brass = new("caa467"), Glass = new("284958"),
        Coral = new("d86239"), Shell = new("e77b45"), DarkCoral = new("ae432d"),
        Eye = new("fff1c7"), Pupil = new("192e31"), Teal = new("438d88"), Purple = new("9358bd");

    public static Node3D Boat(BoatKind kind, int[] weapons)
    {
        int mask = 0;
        for (int i = 0; i < Math.Min(6, weapons.Length); i++) if (weapons[i] > 0) mask |= 1 << i;
        string key = $"boat-{kind}-{mask}";
        if (!Cache.TryGetValue(key, out var mesh))
        {
            var b = new ActorGeometry(); BuildBoat(b, kind, mask); Cache[key] = mesh = b.Mesh(Material);
        }
        return Instance(mesh, key);
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

    static void BuildBoat(ActorGeometry b, BoatKind kind, int mask)
    {
        Color stripe = kind == BoatKind.Mage ? new("685577") : kind == BoatKind.Trawler ? new("43867e") : new("496d77");
        b.Loft(new[] { HullRing(-.055f, .67f), HullRing(.025f, .85f), HullRing(.10f, .965f), HullRing(.165f, 1), HullRing(.205f, 1) }, new[] { DarkWood, stripe, Cream, Wood });
        b.Polygon(HullRing(.191f, .935f), Deck, Vector3.Up);
        // Individual deck boards with narrow dark seams and warm end grain.
        for (float z = -.49f; z < .48f; z += .078f)
        {
            float width = Width(z) * .9f;
            b.Tube(new[] { new Vector3(-width, .194f, z), new Vector3(width, .194f, z) }, .0032f, DarkWood, 5);
        }
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
        b.RoundBox(new(0, .324f, .095f), new(.335f, .257f, .34f), .033f, Cream);
        b.RoundBox(new(0, .474f, .095f), new(.402f, .055f, .415f), .026f, new("f5e5be"));
        b.RoundBox(new(0, .36f, -.08f), new(.226f, .102f, .014f), .009f, Glass);
        b.RoundBox(new(0, .36f, -.092f), new(.013f, .112f, .017f), .004f, Cream);
        foreach (int side in new[] { -1, 1 })
        {
            for (int j = 0; j < 2; j++) b.RoundBox(new(side * .17f, .36f, .017f + .15f * j), new(.015f, .106f, .103f), .007f, Glass);
            b.RoundBox(new(side * .174f, .29f, .1f), new(.012f, .017f, .26f), .004f, Brass);
        }
        b.RoundBox(new(0, .31f, .27f), new(.12f, .20f, .019f), .011f, Wood);
        b.Sphere(new(.036f, .322f, .285f), new(.009f, .009f, .009f), Brass, 8, 5);
        b.RoundBox(new(-.1f, .53f, .18f), new(.066f, .085f, .068f), .012f, DarkWood);
        b.RoundBox(new(-.1f, .578f, .18f), new(.082f, .021f, .084f), .007f, Brass);
        b.Tube(new[] { new Vector3(.11f, .48f, .22f), new Vector3(.11f, .69f, .22f) }, .008f, Wood, 7);
        b.Tube(new[] { new Vector3(.11f, .665f, .22f), new Vector3(.04f, .635f, .22f) }, .008f, Brass, 7);
        if (kind == BoatKind.Mage) Crystal(b, new(0, .247f, -.345f), .95f);
        else if (kind == BoatKind.Trawler)
        {
            b.Sphere(new(0, .25f, -.337f), new(.132f, .045f, .12f), DarkWood);
            b.Ring(new(0, .295f, -.337f), .108f, .017f, Brass);
            b.Sphere(new(0, .309f, -.337f), new(.083f, .049f, .083f), Teal);
            for (int j = 0; j < 4; j++)
            {
                float a = j * Mathf.Tau / 4;
                b.Tube(new[] { new Vector3(.10f * MathF.Cos(a), .3f, -.337f + .10f * MathF.Sin(a)), new Vector3(.13f * MathF.Cos(a), .39f, -.337f + .13f * MathF.Sin(a)) }, .012f, Brass, 7);
            }
        }
        else Cannon(b, new(0, .25f, -.32f), 1);
        // Show the second equipped weapon as a compact stern fitting without masking identity.
        int starter = kind == BoatKind.Cutter ? 0 : kind == BoatKind.Mage ? 5 : 4;
        for (int i = 0; i < 6; i++) if (i != starter && (mask & (1 << i)) != 0)
        {
            var p = new Vector3(0, .22f, .405f);
            if (i == 0 || i == 1) Cannon(b, p, .55f);
            else if (i == 5) Crystal(b, p, .46f);
            else { b.Sphere(p + Vector3.Up * .045f, new(.07f, .055f, .06f), i == 2 ? Glass : Teal); b.Ring(p + Vector3.Up * .074f, .055f, .009f, Brass); }
            break;
        }
    }

    static void Cannon(ActorGeometry b, Vector3 p, float s)
    {
        b.Sphere(p, new Vector3(.11f, .044f, .105f) * s, Wood);
        b.Sphere(p + new Vector3(0, .055f, 0) * s, new Vector3(.077f, .068f, .075f) * s, new("61787a"));
        b.Tube(new[] { p + new Vector3(0, .067f, -.028f) * s, p + new Vector3(0, .089f, -.205f) * s }, .035f * s, Glass, 12);
        b.Tube(new[] { p + new Vector3(0, .087f, -.172f) * s, p + new Vector3(0, .092f, -.215f) * s }, .043f * s, new("8b9a91"), 12);
        b.Sphere(p + new Vector3(0, .093f, -.218f) * s, new Vector3(.03f, .03f, .003f) * s, Pupil, 12, 7);
    }

    static void Crystal(ActorGeometry b, Vector3 p, float s)
    {
        b.Sphere(p, new Vector3(.095f, .035f, .087f) * s, DarkWood);
        b.Tube(new[] { p, p + Vector3.Up * .105f * s }, .029f * s, Brass, 8);
        b.Crystal(p + Vector3.Up * .235f * s, new Vector3(.088f, .20f, .078f) * s, Purple);
        b.Ring(p + Vector3.Up * .11f * s, .063f * s, .012f * s, Brass);
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
            b.Sphere(P(side * .34f, .18f, -.27f), P(.075f, .063f, .10f), Shell, 14, 9);
            b.Tube(new[] { P(side * .304f, .18f, -.315f), P(side * .295f, .175f, -.39f), P(side * .329f, .168f, -.409f) }, new[] { .036f * s, .021f * s, .004f * s }, Coral, 8);
            b.Tube(new[] { P(side * .375f, .18f, -.306f), P(side * .383f, .172f, -.373f), P(side * .348f, .168f, -.408f) }, new[] { .03f * s, .02f * s, .003f * s }, Shell, 8);
            b.Tube(new[] { P(side * .105f, .228f, -.15f), P(side * .12f, .292f, -.20f) }, .016f * s, DarkCoral, 8);
            b.Sphere(P(side * .12f, .293f, -.204f), P(.045f, .051f, .043f), Eye, 14, 9);
            b.Sphere(P(side * .116f, .296f, -.239f), P(.021f, .027f, .012f), Pupil, 12, 8);
            b.Sphere(P(side * .11f - .006f, .308f, -.249f), P(.006f, .007f, .003f), Eye, 8, 5);
            // Small horn and brow connect the eyes to the sculpted shell.
            b.Tube(new[] { P(side * .164f, .255f, -.14f), P(side * .17f, .323f, -.124f) }, new[] { .025f * s, .003f * s }, Coral, 8);
        }
        b.Sphere(P(0, .11f, -.223f), P(.07f, .026f, .008f), DarkWood, 12, 7);
        for (int j = 0; j < (s > 2 ? 14 : 7); j++)
        {
            float a = j * 2.39996f, r = .17f * MathF.Sqrt((j + .5f) / (s > 2 ? 14 : 7));
            float x = MathF.Cos(a) * r, z = .018f + MathF.Sin(a) * r;
            float y = .20f + .127f * MathF.Sqrt(MathF.Max(.1f, 1 - x * x / .061f - (z - .015f) * (z - .015f) / .045f));
            b.Sphere(P(x, y, z), P(.018f, .009f, .017f), Coral, 8, 5);
            if (s > 2 && j % 2 == 0) b.Tube(new[] { P(x, y, z), P(x * 1.07f, y + .068f, z + .014f) }, new[] { .026f * s, .002f * s }, Shell, 8);
        }
    }

    static void Puffer(ActorGeometry b)
    {
        Color gold = new("cfa65d");
        b.Sphere(new(0, .18f, 0), new(.265f, .235f, .25f), gold, 20, 12);
        b.Sphere(new(0, .10f, -.11f), new(.205f, .135f, .17f), Cream);
        for (int j = 0; j < 25; j++)
        {
            float y = .15f + .8f * (j + .5f) / 25, a = j * 2.39996f;
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
        Color skin = new("458b85"), ridge = new("a8b17d");
        var path = new[] { new Vector3(0, -.07f, .69f), new Vector3(-.07f, .12f, .48f), new Vector3(-.13f, .18f, .31f), new Vector3(-.075f, .08f, .13f), new Vector3(.035f, .12f, -.02f), new Vector3(.065f, .37f, -.11f), new Vector3(.035f, .61f, -.15f), new Vector3(0, .72f, -.27f) };
        b.Tube(path, new[] { .024f, .068f, .105f, .12f, .137f, .123f, .11f, .095f }, skin, 14);
        for (int j = 0; j < 6; j++)
        {
            float y = .15f + j * .082f;
            b.Sphere(new(.045f, y, -.146f - j * .005f), new(.094f - j * .003f, .044f, .04f), Cream, 12, 8);
        }
        b.Sphere(new(0, .713f, -.284f), new(.133f, .115f, .159f), skin);
        b.Sphere(new(0, .663f, -.383f), new(.091f, .042f, .095f), DarkWood);
        b.Sphere(new(0, .64f, -.366f), new(.091f, .028f, .078f), Cream);
        b.Sphere(new(0, .701f, -.387f), new(.11f, .054f, .10f), skin);
        foreach (int side in new[] { -1, 1 })
        {
            Eyes(b, new(side * .10f, .752f, -.341f), .041f);
            b.Tube(new[] { new Vector3(side * .075f, .79f, -.225f), new Vector3(side * .093f, .88f, -.197f) }, new[] { .028f, .002f }, ridge, 8);
            b.Sphere(new(side * .041f, .724f, -.467f), new(.012f, .012f, .006f), Pupil, 8, 5);
        }
        for (int j = 1; j < path.Length - 1; j++)
        {
            var p = path[j] + new Vector3(0, j < 4 ? .085f : .045f, j < 4 ? 0 : .095f);
            b.Tube(new[] { p, p + new Vector3(0, .09f, .043f) }, new[] { .035f, .001f }, ridge, 8);
        }
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
