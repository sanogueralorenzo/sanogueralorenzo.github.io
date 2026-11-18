using BoatsNBeasts.Core;
using Godot;
namespace BoatsNBeasts;

static class BeaconArt
{
    public static Node3D Build(Beacon beacon)
    {
        var root = new Node3D { Position = NativeStage3D.Point(beacon.Position) };
        var brass = EffectsGeometry.Matte("c68e47");
        var timber = EffectsGeometry.Matte("6d3d2b");
        var red = EffectsGeometry.Matte("a74537");
        Add(root, .12f, .46f, .36f, 0, timber, 8);
        Add(root, .43f, .43f, .13f, .23f, red, 8);
        Add(root, .09f, .18f, .58f, .57f, timber, 8);
        Add(root, .22f, .24f, .09f, .87f, brass, 8);

        var glow = new StandardMaterial3D
        {
            AlbedoColor = new("ffe0a1"), EmissionEnabled = true, Emission = NauticalPalette.Gold,
            EmissionEnergyMultiplier = .75f, Roughness = .3f
        };
        Add(root, .135f, .16f, .24f, 1.02f, glow, 6).Name = "Lamp";
        Add(root, .04f, .24f, .22f, 1.24f, brass, 8);
        Add(root, .045f, .045f, .09f, 1.38f, brass, 8);
        return root;
    }

    static MeshInstance3D Add(Node3D root, float top, float baseRadius, float height, float y, Material material, int sides)
    {
        var mesh = new MeshInstance3D
        {
            Mesh = new CylinderMesh { TopRadius = top, BottomRadius = baseRadius, Height = height, RadialSegments = sides },
            Position = new(0, y, 0),
            MaterialOverride = material
        };
        root.AddChild(mesh);
        return mesh;
    }

    public static void Advance(Node3D root, Beacon beacon, float time)
    {
        var home = NativeStage3D.Point(beacon.Position);
        root.Position = home + Vector3.Up * Mathf.Sin(time * 1.8f + home.X) * .045f;
        root.Rotation = new(Mathf.Sin(time * 1.55f + home.Z) * .08f, 0, Mathf.Sin(time * 1.13f + home.X) * .07f);
        var lamp = (StandardMaterial3D)root.GetNode<MeshInstance3D>("Lamp").MaterialOverride;
        lamp.Emission = beacon.Lit ? NauticalPalette.Aqua : NauticalPalette.Gold;
        lamp.EmissionEnergyMultiplier = beacon.Lit ? 1.25f : .65f + beacon.Progress * .75f;
    }
}
