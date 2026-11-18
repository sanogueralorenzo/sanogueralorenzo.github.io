using Godot;
using BoatsNBeasts.Core;
using System;

namespace BoatsNBeasts;

public static partial class ActorArt3D
{
    static readonly Vector3 BoatScale = new(BoatRig.Scale.X, BoatRig.Scale.Y, BoatRig.Scale.Z);
    static Vector3 ArtPosition(WeaponMount mount) => new(mount.Position.X, mount.Position.Y, mount.Position.Z);

    public static void AnimateBoat(Node3D root, float clock, float speed, float cannonAngle = 0, float harpoonAngle = 0, float heel = 0)
    {
        Animate(root, clock, speed);
        var sculpture = root.GetChild<Node3D>(0);
        sculpture.Rotation += new Vector3(-speed * .011f, 0, heel);
        sculpture.Position += Vector3.Up * Mathf.Sin(clock * 3.1f) * Mathf.Min(speed, 4) * .004f;
        if (sculpture.GetNodeOrNull<Node3D>("AimCannon") is { } cannon)
            cannon.Rotation = new(0, cannonAngle, 0);
        if (sculpture.GetNodeOrNull<Node3D>("AimHarpoon") is { } harpoon)
            harpoon.Rotation = new(0, harpoonAngle, 0);
    }

    static void AddAimedWeapon(Node3D root, int weapon, int rank, WeaponMount mount)
    {
        string key = $"aim-{weapon}-{rank}-{mount.Size}";
        if (!Cache.TryGetValue(key, out var mesh))
        {
            var b = new ActorGeometry(); Equipment(b, weapon, rank, Vector3.Zero, mount.Size);
            b.Scale(BoatScale); Cache[key] = mesh = b.Mesh(Material);
        }
        root.GetChild(0).AddChild(new MeshInstance3D { Name = weapon == (int)WeaponKind.Cannon ? "AimCannon" : "AimHarpoon", Mesh = mesh, Position = ArtPosition(mount) * BoatScale,
            CastShadow = GeometryInstance3D.ShadowCastingSetting.On });
    }

    static void Equipment(ActorGeometry b, int weapon, int rank, Vector3 p, float size)
    {
        // Include rank in the cache key because refits change geometry.
        float s = size * (1 + .035f * Math.Min(5, rank - 1));
        Vector3 P(float x, float y, float z) => p + new Vector3(x, y, z) * s;
        Vector3 R(float x, float y, float z) => new Vector3(x, y, z) * s;
        Color iron = new("344b53"), copper = new("b77749");
        b.Sphere(p, R(.115f, .036f, .108f), DarkWood, 16, 8);
        switch (weapon)
        {
            case 0:
                b.Sphere(P(0, .074f, .01f), R(.094f, .085f, .115f), iron);
                b.Tube(new[] { P(-.12f, .065f, .008f), P(.12f, .065f, .008f) }, .032f * s, Brass, 10);
                b.Tube(new[] { P(0, .088f, -.025f), P(0, .108f, -.255f) }, new[] { .058f * s, .042f * s }, iron, 14);
                b.Tube(new[] { P(0, .105f, -.218f), P(0, .111f, -.269f) }, .054f * s, new("63777a"), 14);
                b.Sphere(P(0, .112f, -.274f), R(.037f, .037f, .004f), Pupil, 14, 8);
                for (int i = 0; i < Math.Min(4, rank); i++)
                    b.Tube(new[] { P(0, .091f + i * .0023f, -.05f - i * .027f), P(0, .092f + i * .0023f, -.062f - i * .027f) }, (.059f - i * .002f) * s, Brass, 14);
                break;
            case 1:
                b.RoundBox(P(0, .051f, -.035f), R(.13f, .095f, .235f), .016f * s, Wood);
                b.Tube(new[] { P(0, .116f, .095f), P(0, .116f, -.27f) }, .014f * s, new("8eaaa9"), 9);
                b.Crystal(P(0, .116f, -.263f), R(.026f, .028f, .055f), new("a5bbad"));
                foreach (int side in new[] { -1, 1 })
                {
                    b.Tube(new[] { P(0, .11f, -.115f), P(side * .13f, .10f, -.045f), P(side * .15f, .10f, .025f) }, .019f * s, copper, 8);
                    b.Tube(new[] { P(side * .15f, .10f, .025f), P(0, .113f, .063f) }, .005f * s, Cream, 6);
                }
                b.Tube(new[] { P(-.08f, .07f, .065f), P(.08f, .07f, .065f) }, .033f * s, Brass, 10);
                RankBands(b, p, s, rank, .045f);
                break;
            case 2:
                b.Sphere(P(0, .077f, 0), R(.089f, .082f, .086f), iron);
                for (int i = 0; i < 7; i++)
                {
                    float a = i * Mathf.Tau / 7;
                    b.Tube(new[] { P(MathF.Cos(a) * .067f, .11f, MathF.Sin(a) * .067f), P(MathF.Cos(a) * .114f, .135f, MathF.Sin(a) * .114f) }, new[] { .019f * s, .009f * s }, Brass, 7);
                }
                b.Sphere(P(0, .161f, 0), R(.025f, .024f, .025f), Coral);
                RankBands(b, p, s, rank, .018f);
                break;
            case 3:
                b.Tube(new[] { P(0, .018f, 0), P(0, .19f, 0) }, .032f * s, Glass, 10);
                for (int i = 0; i < 4 + Math.Min(3, rank - 1); i++)
                    b.Ring(P(0, .045f + i * .023f, 0), .057f * s, .009f * s, copper);
                b.Sphere(P(0, .215f, 0), R(.067f, .066f, .067f), Teal);
                foreach (int side in new[] { -1, 1 })
                    b.Tube(new[] { P(side * .072f, .016f, 0), P(side * .105f, .16f, 0), P(side * .069f, .235f, 0) }, .013f * s, Brass, 8);
                break;
            case 4:
                b.Ring(P(0, .048f, 0), .111f * s, .018f * s, Brass);
                b.Sphere(P(0, .057f, 0), R(.075f, .047f, .075f), Teal);
                for (int i = 0; i < 4; i++)
                {
                    float a = i * Mathf.Tau / 4;
                    var end = P(.128f * MathF.Cos(a), .113f, .128f * MathF.Sin(a));
                    b.Tube(new[] { P(.09f * MathF.Cos(a), .036f, .09f * MathF.Sin(a)), end }, .014f * s, copper, 8);
                    b.Sphere(end, R(.026f, .023f, .026f), Teal, 10, 6);
                }
                RankBands(b, p, s, rank, .012f);
                break;
            case 5:
                Crystal(b, p, s);
                RankBands(b, p, s, rank, .055f);
                break;
        }
    }

    static void RankBands(ActorGeometry b, Vector3 p, float s, int rank, float height)
    {
        for (int i = 0; i < Math.Min(4, rank); i++)
            b.Ring(p + Vector3.Up * (height + i * .018f) * s, .063f * s, .006f * s, Brass);
    }
}
