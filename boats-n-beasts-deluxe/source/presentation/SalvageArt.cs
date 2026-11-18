using Godot;
using V2 = System.Numerics.Vector2;
namespace BoatsNBeasts;

static class SalvageArt
{
    public static Node3D Build()
    {
        var root = new Node3D();
        var geometry = new ActorGeometry();
        Color floatWood = new("6f4931"), lid = new("b87a43"), iron = new("383c38"),
            gold = new("ecc16c"), pennant = new("df6c47");
        foreach (float z in new[] { -.24f, .24f })
        {
            geometry.Tube([new(-.54f, .075f, z), new(.54f, .075f, z)], .10f, floatWood, 8);
            foreach (float x in new[] { -.36f, .36f })
                geometry.Tube([new(x - .025f, .075f, z), new(x + .025f, .075f, z)], .107f, gold, 8);
        }

        geometry.RoundBox(new(0, .23f, 0), new(.66f, .33f, .43f), .037f, lid);
        foreach (float x in new[] { -.235f, .235f })
            geometry.RoundBox(new(x, .242f, 0), new(.07f, .34f, .457f), .015f, iron);
        geometry.RoundBox(new(0, .26f, .227f), new(.11f, .108f, .028f), .014f, gold);
        geometry.Tube([new(-.28f, .21f, -.29f), new(-.28f, .94f, -.29f)], .019f, floatWood, 8);
        Vector3[] flag = [new(-.28f, .92f, -.29f), new(.18f, .82f, -.34f), new(-.28f, .68f, -.29f)];
        geometry.Polygon(flag, pennant, Vector3.Back);
        geometry.Polygon(flag, pennant, Vector3.Forward);
        root.AddChild(new MeshInstance3D { Mesh = geometry.Mesh(DioramaSurface.Material) });
        return root;
    }

    public static void Advance(Node3D root, V2 position, float time, V2 tow)
    {
        root.Position = NativeStage3D.Point(position, Mathf.Sin(time * 2.7f) * .045f);
        float heading = tow.LengthSquared() > 1 ? -Mathf.Atan2(tow.Y, tow.X) : .28f;
        root.Rotation = new(Mathf.Cos(time * 1.7f) * .095f, heading, Mathf.Sin(time * 2.3f) * .083f);
    }
}
