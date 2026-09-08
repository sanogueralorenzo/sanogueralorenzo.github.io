using Godot;

namespace CozySora;

/// <summary>Park palette and grouped construction, composing shared mesh and collision mechanisms.</summary>
public sealed class DaanGeometry
{
    public Func<float, float, float>? GroundHeight { get; set; }
    public Node3D Root { get; }
    public StaticBody3D Body { get; }
    private readonly Dictionary<(string, string, int), Group> _groups = new();
    private readonly Dictionary<(string, int), Material> _materials = new();
    private readonly Dictionary<string, Mesh> _meshes = new();
    private sealed record Group(Mesh Mesh, Material Material)
    {
        public List<Transform3D> Transforms { get; } = new();
    }

    public DaanGeometry(Node3D parent)
    {
        Root = parent;
        Body = new StaticBody3D { Name = "Park and neighborhood collision" };
        Root.AddChild(Body);
    }

    public Material Material(string color, int finish = 0)
    {
        var key = (color, finish);
        if (_materials.TryGetValue(key, out var cached)) return cached;
        var material = new ShaderMaterial { Shader = GD.Load<Shader>("res://maps/daan_gardens/surface.gdshader") };
        material.SetShaderParameter("tint", new Color(color));
        material.SetShaderParameter("finish", finish);
        _materials.Add(key, material);
        return material;
    }

    public Mesh Shape(string kind)
    {
        if (_meshes.TryGetValue(kind, out var cached)) return cached;
        var mesh = kind switch
        {
            "box" => (Mesh)CozyPrimitives.BoxMesh(),
            "sphere" => CozyPrimitives.SphereMesh(),
            "branch_base" => CozyTreeForms.Limb(.375f),
            "branch_tip" => CozyTreeForms.Limb(.3333333f),
            _ => CozyPrimitives.CylinderMesh(.5f, .5f, 1, 12)
        };
        _meshes.Add(kind, mesh);
        return mesh;
    }

    public void Add(string kind, Vector3 position, Vector3 size, string color, Vector3 rotation = default, bool solid = false, int finish = 0)
    {
        var key = (kind, color, finish);
        if (!_groups.TryGetValue(key, out var group)) _groups.Add(key, group = new(Shape(kind), Material(color, finish)));
        group.Transforms.Add(new Transform3D(Basis.FromEuler(rotation) * Basis.FromScale(size), position));
        if (solid) CozyCollision.Box(Body, position, size, rotation);
    }

    public void Box(Vector3 position, Vector3 size, string color, bool solid = false, float yaw = 0, int finish = 0) =>
        Add("box", position, size, color, new Vector3(0, yaw, 0), solid, finish);

    public void Beam(Vector3 a, Vector3 b, float radius, string color) =>
        Add("cylinder", (a + b) * .5f, new Vector3(radius * 2, a.DistanceTo(b), radius * 2), color,
            new Quaternion(Vector3.Up, (b - a).Normalized()).GetEuler());

    public MeshInstance3D Mesh(Mesh mesh, string color, bool solid = false, int finish = 0)
    {
        var node = CozyPrimitives.Instance(Root, mesh, Vector3.Zero, Material(color, finish));
        if (solid) CozyCollision.Mesh(Body, mesh);
        return node;
    }

    public void Ribbon(IReadOnlyList<Vector3> points, float width, string color, int finish = 1, bool solid = false, bool drape = true)
    {
        var surface = new SurfaceTool();
        surface.Begin(Godot.Mesh.PrimitiveType.Triangles);
        var pairs = new (Vector3 A, Vector3 B)[points.Count];
        for (int i = 0; i < points.Count; i++)
        {
            var before = points[Math.Max(0, i - 1)];
            var after = points[Math.Min(points.Count - 1, i + 1)];
            if (points[0].IsEqualApprox(points[^1]) && (i == 0 || i == points.Count - 1))
            {
                before = points[^2];
                after = points[1];
            }
            var side = (after - before).Cross(Vector3.Up).Normalized() * width * .5f;
            var a = points[i] - side;
            var b = points[i] + side;
            if (drape && GroundHeight is { } height)
            {
                float lift = points[i].Y - height(points[i].X, points[i].Z);
                a.Y = height(a.X, a.Z) + lift;
                b.Y = height(b.X, b.Z) + lift;
            }
            pairs[i] = (a, b);
        }
        for (int i = 0; i < points.Count - 1; i++)
            foreach (var vertex in new[] { pairs[i].A, pairs[i + 1].A, pairs[i + 1].B, pairs[i].A, pairs[i + 1].B, pairs[i].B })
                surface.AddVertex(vertex);
        surface.GenerateNormals();
        Mesh(surface.Commit(), color, solid, finish);
    }

    public void Disc(Vector3 at, float radius, string color, int finish = 1)
    {
        var surface = new SurfaceTool();
        surface.Begin(Godot.Mesh.PrimitiveType.Triangles);
        float lift = GroundHeight is { } height ? at.Y - height(at.X, at.Z) : 0;
        for (int i = 0; i < 64; i++)
            foreach (var vertex in new[] { at,
            at + new Vector3(Mathf.Cos(i * Mathf.Tau / 64), 0, Mathf.Sin(i * Mathf.Tau / 64)) * radius,
            at + new Vector3(Mathf.Cos((i + 1) * Mathf.Tau / 64), 0, Mathf.Sin((i + 1) * Mathf.Tau / 64)) * radius })
            {
                var position = vertex;
                if (GroundHeight is { } ground) position.Y = ground(position.X, position.Z) + lift;
                surface.AddVertex(position);
            }
        surface.GenerateNormals();
        Mesh(surface.Commit(), color, false, finish);
    }

    public void Label(string text, Vector3 at, float width, string color = "ede8cd", float yaw = 0)
    {
        Root.AddChild(new Label3D
        {
            Text = text,
            Position = at,
            Rotation = new(0, yaw, 0),
            FontSize = 64,
            PixelSize = Mathf.Min(width / Mathf.Max(1, text.Length * 36.48f), .008f),
            Modulate = new Color(color),
            OutlineSize = 0,
            Shaded = true,
            DoubleSided = false,
            VisibilityRangeEnd = 65
        });
    }

    public void Finish()
    {
        foreach (var group in _groups.Values)
            CozyMeshBatches.Spatial(Root, group.Mesh, group.Material, group.Transforms, "Crafted park", 32);
        _groups.Clear();
    }
}
