using Godot;

namespace BoatsNBeasts;

// Shared procedural surface for the game and art preview. Radius is in world units.
public partial class Whirlpool3D : Node3D
{
    public const float WaterCutout = .80f;
    static ArrayMesh? mesh;
    static ShaderMaterial? material;
    static readonly StandardMaterial3D ShardMaterial = new() { VertexColorUseAsAlbedo = true,
        VertexColorIsSrgb = true, Roughness = 1, EmissionEnabled = true,
        Emission = new("75dcc0"), EmissionEnergyMultiplier = .22f };
    public float Radius { get; private set; }

    public static Whirlpool3D Create(float radius, uint seed)
    {
        material ??= new ShaderMaterial { Shader = GD.Load<Shader>("res://source/presentation/whirlpool.gdshader") };
        mesh ??= BuildMesh();
        var root = new Whirlpool3D { Name = "Whirlpool", Radius = radius, Rotation = new(0, seed % 628 * .01f, 0) };
        root.AddChild(new MeshInstance3D { Mesh = mesh, MaterialOverride = material, Scale = Vector3.One * radius,
            CastShadow = GeometryInstance3D.ShadowCastingSetting.Off });
        var shards = new ActorGeometry();
        float[] angles = [.13f,.47f,.92f,1.35f,1.79f,2.08f,2.62f,3.14f,3.47f,4.12f,4.73f,5.30f,5.87f];
        for (int i = 0; i < angles.Length; i++)
        {
            float angle = angles[i], reach = 1.03f + .045f * Mathf.Sin(i * 2.7f);
            float size = 1.12f + .32f * Mathf.Sin(i * 1.8f + 1);
            shards.Crystal(new(Mathf.Cos(angle) * reach, .035f, Mathf.Sin(angle) * reach),
                new Vector3(.034f, .089f, .036f) * size, new Color("83efcf"));
        }
        root.AddChild(new MeshInstance3D { Name = "WaterShards", Mesh = shards.Mesh(ShardMaterial),
            Scale = Vector3.One * radius, CastShadow = GeometryInstance3D.ShadowCastingSetting.Off });
        return root;
    }

    public static void Advance(float clock) => material?.SetShaderParameter("clock", clock);

    static ArrayMesh BuildMesh()
    {
        const int rings = 32, sides = 96;
        var surface = new SurfaceTool(); surface.Begin(Mesh.PrimitiveType.Triangles);
        Vector3 Point(float r, float angle)
        {
            // A wide throat and steep bowl read as a water-filled funnel, not a pinwheel tip.
            float variation = (.018f * Mathf.Sin(angle * 3) + .011f * Mathf.Cos(angle * 5)) * Mathf.SmoothStep(.20f, .38f, r);
            float wall = Mathf.SmoothStep(.20f, .58f, r + variation);
            float depth = -.36f * (1 - wall);
            float lip = .014f * Mathf.Exp(-Mathf.Pow((r - .61f) / .12f, 2));
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
