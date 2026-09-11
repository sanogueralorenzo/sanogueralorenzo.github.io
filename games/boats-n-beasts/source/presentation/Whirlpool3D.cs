using Godot;

namespace BoatsNBeasts;

// Shared procedural surface for the game and art preview. Radius is in world units.
public partial class Whirlpool3D : Node3D
{
    public const float WaterCutout = .80f;
    static ArrayMesh? mesh;
    static ShaderMaterial? material;
    public float Radius { get; private set; }

    public static Whirlpool3D Create(float radius, uint seed)
    {
        material ??= new ShaderMaterial { Shader = GD.Load<Shader>("res://source/presentation/whirlpool.gdshader") };
        mesh ??= BuildMesh();
        var root = new Whirlpool3D { Name = "Whirlpool", Radius = radius, Rotation = new(0, seed % 628 * .01f, 0) };
        root.AddChild(new MeshInstance3D { Mesh = mesh, MaterialOverride = material, Scale = Vector3.One * radius,
            CastShadow = GeometryInstance3D.ShadowCastingSetting.Off });
        return root;
    }

    public static void Advance(float clock) => material?.SetShaderParameter("clock", clock);

    static ArrayMesh BuildMesh()
    {
        const int rings = 28, sides = 96;
        var surface = new SurfaceTool(); surface.Begin(Mesh.PrimitiveType.Triangles);
        Vector3 Point(float r, float angle)
        {
            // A broad bowl tightens into a deep throat. The outer shelf meets sea level.
            float bowl = Mathf.Clamp((.78f - r) / .70f, 0, 1);
            float depth = -.54f * bowl * bowl;
            float lip = .018f * Mathf.Exp(-Mathf.Pow((r - .74f) / .12f, 2));
            return new(Mathf.Cos(angle) * r, depth + lip + .006f, Mathf.Sin(angle) * r);
        }
        void Triangle(Vector3 a, Vector3 b, Vector3 c)
        {
            if ((b - a).Cross(c - a).LengthSquared() < 1e-14f) return;
            foreach (var p in new[] { a, c, b })
            {
                surface.SetNormal(Vector3.Up); surface.SetUV(new(p.X, p.Z)); surface.AddVertex(p);
            }
        }
        for (int ring = 0; ring < rings; ring++) for (int side = 0; side < sides; side++)
        {
            float a = side * Mathf.Tau / sides, b = (side + 1) * Mathf.Tau / sides;
            float inner = ring / (float)rings, outer = (ring + 1) / (float)rings;
            Triangle(Point(inner, a), Point(outer, a), Point(outer, b));
            Triangle(Point(inner, a), Point(outer, b), Point(inner, b));
        }
        return surface.Commit();
    }
}
