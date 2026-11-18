using Godot;

namespace CozySora;

/// <summary>Harbor's static geometry is batched by material and 40 metre spatial cell.</summary>
public sealed class HarborGeometry
{
    public Node3D Root { get; }
    public PhysicsBody3D Collision { get; }
    public Func<float, float, float>? GroundHeight { get; set; }
    public Func<float, float, float, bool>? PlantClearance { get; set; }
    private readonly Dictionary<(string, string, string, Vector2I), Group> _groups = new();
    private readonly Dictionary<(string, string), Material> _materials = new();
    private readonly Dictionary<string, Mesh> _primitives = new();
    private Texture2D? _leafTexture;
    private sealed record Group(string Kind, Material Material, Vector2I Cell)
    {
        public List<Transform3D> Transforms { get; } = new();
    }
    private static readonly int[] Triangles = [0, 1, 2, 0, 2, 3];
    private static readonly Vector2[] Quad = [new(0, 0), new(1, 0), new(1, 1), new(0, 1)];

    public HarborGeometry(Node3D parent, bool moving = false)
    {
        Root = parent;
        Collision = moving ? new AnimatableBody3D() : new StaticBody3D();
        Collision.Name = "District collision";
        Root.AddChild(Collision);
    }

    public Material Material(string color, string kind = "plaster")
    {
        var key = (color, kind);
        if (_materials.TryGetValue(key, out var cached)) return cached;
        var material = new ShaderMaterial();
        if (kind == "foliage")
        {
            material.Shader = GD.Load<Shader>("res://maps/harbor_hills/leaves.gdshader");
            material.SetShaderParameter("leaf_cards", true);
            _leafTexture ??= HarborTextures.LeafSpray();
            material.SetShaderParameter("leaf_texture", _leafTexture);
            material.SetShaderParameter("base_color", new Color(color));
        }
        else
        {
            material.Shader = GD.Load<Shader>("res://maps/harbor_hills/surface.gdshader");
            material.SetShaderParameter("base_color", new Color(color));
            material.SetShaderParameter("grain", kind == "metal" ? .045f : .12f);
            material.SetShaderParameter("pattern", kind switch
            {
                "siding" => 1,
                "brick" => 2,
                "roof" => 3,
                "asphalt" => 4,
                "paving" => 5,
                _ => 0
            });
        }
        _materials.Add(key, material);
        return material;
    }

    public Mesh Shape(string kind)
    {
        if (_primitives.TryGetValue(kind, out var cached)) return cached;
        Mesh mesh;
        switch (kind)
        {
            case "box": mesh = CozyPrimitives.BoxMesh(); break;
            case "sphere": mesh = CozyPrimitives.SphereMesh(); break;
            case "branch": mesh = CozyPrimitives.CylinderMesh(.5f, .26f, 1, 9); break;
            case "leaf":
                var surface = new SurfaceTool();
                surface.Begin(Mesh.PrimitiveType.Triangles);
                var random = new RandomNumberGenerator { Seed = 491 };
                Vector2[] corners = [new(-1, -1), new(1, -1), new(1, 1), new(-1, 1)];
                for (int i = 0; i < 28; i++)
                {
                    var center = new Vector3(random.RandfRange(-.48f, .48f), random.RandfRange(-.35f, .35f), random.RandfRange(-.48f, .48f));
                    var normal = new Vector3(random.RandfRange(-1, 1), random.RandfRange(.15f, 1), random.RandfRange(-1, 1)).Normalized();
                    var basis = new Basis(new Quaternion(Vector3.Forward, normal));
                    float radius = random.RandfRange(.22f, .35f);
                    float shade = random.RandfRange(.72f, 1.22f);
                    surface.SetColor(new Color(shade, shade, shade));
                    foreach (int j in Triangles)
                    {
                        surface.SetUV(corners[j] * .5f + Vector2.One * .5f);
                        surface.SetNormal((center * new Vector3(1, 2, 1) + normal * .18f + Vector3.Up * .2f).Normalized());
                        surface.AddVertex(center + basis * new Vector3(corners[j].X * radius, corners[j].Y * radius, 0));
                    }
                }
                mesh = surface.Commit();
                break;
            default: mesh = CozyPrimitives.CylinderMesh(.5f, .5f, 1); break;
        }
        _primitives.Add(kind, mesh);
        return mesh;
    }

    public void Add(string kind, Vector3 position, Vector3 size, string color, Vector3 rotation = default,
        bool solid = false, string finish = "plaster")
    {
        if (kind == "leaf")
        {
            if (PlantClearance?.Invoke(position.X, position.Z, .4f) == true) return;
            finish = "foliage";
        }
        var transform = new Transform3D(Basis.FromEuler(rotation) * Basis.FromScale(size), position);
        var cell = new Vector2I(Mathf.FloorToInt(position.X / 40), Mathf.FloorToInt(position.Z / 40));
        var key = (kind, color, finish, cell);
        if (!_groups.TryGetValue(key, out var group)) _groups.Add(key, group = new(kind, Material(color, finish), cell));
        group.Transforms.Add(transform);
        if (solid) BoxCollision(position, size, rotation);
    }

    public void Box(Vector3 position, Vector3 size, string color, bool solid = false, float yaw = 0, string finish = "plaster") =>
        Add("box", position, size, color, new Vector3(0, yaw, 0), solid, finish);

    public void BoxCollision(Vector3 position, Vector3 size, Vector3 rotation = default) => CozyCollision.Box(Collision, position, size, rotation);

    public void Beam(Vector3 a, Vector3 b, float radius, string color)
    {
        var delta = b - a;
        Add("cylinder", (a + b) * .5f, new Vector3(radius * 2, delta.Length(), radius * 2), color,
            new Quaternion(Vector3.Up, delta.Normalized()).GetEuler(), false, "metal");
    }

    public void Branch(Vector3 a, Vector3 b, float radius, string color)
    {
        var delta = b - a;
        Add("branch", (a + b) * .5f, new Vector3(radius * 2, delta.Length(), radius * 2), color,
            new Quaternion(Vector3.Up, delta.Normalized()).GetEuler());
        if (radius >= .065f) CozyCollision.Limb(Collision, a, b, radius * .8f);
    }

    public void Ribbon(IReadOnlyList<Vector3> points, float width, string color, bool solid = false, bool drape = true, string finish = "plaster")
    {
        var surface = new SurfaceTool();
        surface.Begin(Mesh.PrimitiveType.Triangles);
        for (int i = 0; i < points.Count - 1; i++)
        {
            var a = points[i];
            var b = points[i + 1];
            var side = (b - a).Cross(Vector3.Up).Normalized() * width * .5f;
            Vector3[] corners = [a - side, b - side, b + side, a + side];
            if (drape && GroundHeight is { } height)
            {
                float clearanceA = a.Y - height(a.X, a.Z);
                float clearanceB = b.Y - height(b.X, b.Z);
                for (int j = 0; j < 4; j++) corners[j].Y = height(corners[j].X, corners[j].Z) + (j is 0 or 3 ? clearanceA : clearanceB);
            }
            foreach (int j in Triangles) surface.AddVertex(corners[j]);
            if (solid && !drape)
            {
                foreach (var edge in new[] { (0, 1), (2, 3) })
                {
                    var left = corners[edge.Item1];
                    var right = corners[edge.Item2];
                    foreach (var vertex in new[] { left, right, right - Vector3.Up * .18f, left, right - Vector3.Up * .18f, left - Vector3.Up * .18f })
                        surface.AddVertex(vertex);
                }
            }
        }
        FinishSurface(surface, color, finish, solid);
    }

    public void Semicircle(Vector2 center, Vector2 forward, float inner, float outer, float lift, string color,
        bool solid = false, string finish = "plaster")
    {
        var surface = new SurfaceTool();
        surface.Begin(Mesh.PrimitiveType.Triangles);
        var side = forward.Orthogonal();
        int bands = Mathf.CeilToInt((outer - inner) / .9f);
        for (int ring = 0; ring < bands; ring++)
            for (int segment = 0; segment < 48; segment++)
                foreach (int index in Triangles)
                {
                    var corner = Quad[index];
                    float radius = Mathf.Lerp(inner, outer, (ring + corner.X) / bands);
                    float angle = Mathf.Pi * (segment + corner.Y) / 48;
                    var at = center + (side * Mathf.Cos(angle) + forward * Mathf.Sin(angle)) * radius;
                    surface.AddVertex(new Vector3(at.X, GroundHeight!(at.X, at.Y) + lift, at.Y));
                }
        FinishSurface(surface, color, finish, solid);
    }

    private void FinishSurface(SurfaceTool surface, string color, string finish, bool solid)
    {
        surface.GenerateNormals();
        var mesh = surface.Commit();
        Root.AddChild(new MeshInstance3D { Mesh = mesh, MaterialOverride = Material(color, finish) });
        if (solid) CozyCollision.Mesh(Collision, mesh);
    }

    public void Label(string text, Vector3 position, float width, string color = "f4eedb", float yaw = 0, int fontSize = 64)
    {
        Root.AddChild(new Label3D
        {
            Text = text,
            FontSize = fontSize,
            PixelSize = Mathf.Min(width / Mathf.Max(1, text.Length * fontSize * .57f), .5f / fontSize),
            Modulate = new Color(color),
            Position = position,
            Rotation = new(0, yaw, 0),
            OutlineSize = 0,
            NoDepthTest = false,
            Shaded = true,
            DoubleSided = false,
            VisibilityRangeEnd = 85
        });
    }

    public void Finish()
    {
        foreach (var group in _groups.Values)
        {
            var origin = new Vector3(group.Cell.X * 40 + 20, 0, group.Cell.Y * 40 + 20);
            CozyMeshBatches.Instances(Root, Shape(group.Kind), group.Material, group.Transforms, origin, "Crafted district");
        }
        _groups.Clear();
    }

    public void Cloth(Vector3 at, Vector2 size, string color, float yaw = 0)
    {
        var surface = new SurfaceTool();
        surface.Begin(Mesh.PrimitiveType.Triangles);
        for (int y = 0; y < 6; y++)
            for (int x = 0; x < 6; x++)
                foreach (int index in Triangles)
                {
                    var uv = (new Vector2(x, y) + Quad[index]) / 6;
                    surface.SetUV(uv);
                    surface.SetNormal(Vector3.Forward);
                    surface.AddVertex(new Vector3((uv.X - .5f) * size.X, -uv.Y * size.Y, 0));
                }
        var material = new ShaderMaterial { Shader = GD.Load<Shader>("res://maps/harbor_hills/cloth.gdshader") };
        material.SetShaderParameter("tint", new Color(color));
        Root.AddChild(new MeshInstance3D { Mesh = surface.Commit(), Position = at, Rotation = new(0, yaw, 0), MaterialOverride = material });
    }
}
