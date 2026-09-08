using Godot;
using BoatsNBeasts.Core;
using System;

namespace BoatsNBeasts;

public static partial class ActorArt3D
{
    static readonly Vector3 BoatScale = new(1.22f, 1.15f, 1.30f);
    static int Starter(BoatKind kind) => kind == BoatKind.Cutter ? 0 : kind == BoatKind.Trawler ? 4 : 5;

    /// <summary>relativeAimAngle is a Godot Y rotation in radians relative to the boat's -Z bow.</summary>
    public static void AnimateBoat(Node3D root, float clock, float speed, float relativeAimAngle)
    {
        Animate(root, clock, speed);
        if (root.GetChildCount() == 0) return;
        foreach (Node child in root.GetChild(0).GetChildren())
            if (child is Node3D fitting && fitting.Name.ToString().StartsWith("Aim", StringComparison.Ordinal))
                fitting.Rotation = new(0, relativeAimAngle, 0);
    }

    static void AddAimedWeapon(Node3D root, int weapon, int rank, Vector3 position, float size, string name)
    {
        string key = $"aim-{weapon}-{rank}-{size}";
        if (!Cache.TryGetValue(key, out var mesh))
        {
            var b = new ActorGeometry(); Equipment(b, weapon, rank, Vector3.Zero, size);
            b.Scale(BoatScale); Cache[key] = mesh = b.Mesh(Material);
        }
        root.GetChild(0).AddChild(new MeshInstance3D { Name = name, Mesh = mesh, Position = position * BoatScale,
            CastShadow = GeometryInstance3D.ShadowCastingSetting.On });
    }

    static void Equipment(ActorGeometry b, int weapon, int rank, Vector3 p, float size)
    {
        // Rank is part of the cached mesh signature. Each refit adds a visible collar and modest volume.
        float s = size * (1 + .035f * Math.Min(5, rank - 1));
        Vector3 P(float x, float y, float z) => p + new Vector3(x, y, z) * s;
        Vector3 R(float x, float y, float z) => new Vector3(x, y, z) * s;
        Color iron = new("344b53"), copper = new("b77749");
        b.Sphere(p, R(.115f, .036f, .108f), DarkWood, 16, 8);
        switch (weapon)
        {
            case 0:
                // A broad rounded trunnion and long dark barrel read as an actual naval cannon.
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
