using Godot;

namespace CozySora;

public static class SeabreezeHydrangeas
{
    public static void Plant(Node3D parent, SeabreezeWorld world)
    {
        var random = new RandomNumberGenerator { Seed = 6103 };
        var material = new ShaderMaterial { Shader = GD.Load<Shader>("res://maps/seabreeze_village/hydrangea.gdshader") };
        foreach (string hue in new[] { "748bd3", "a589c7", "849ccd" })
        {
            var flower = BuildStem(random, new Color(hue));
            var plants = new List<Transform3D>();
            foreach (var patch in new Vector2[] { new(-3, -7.4f), new(1.7f, -7.5f), new(8, -7.8f),
                new(14, -7.9f), new(-14, 7.1f), new(-17, 9.6f) })
            {
                for (int i = 0; i < 9; i++)
                {
                    float angle = random.Randf() * Mathf.Tau;
                    float radius = Mathf.Sqrt(random.Randf());
                    float x = patch.X + Mathf.Cos(angle) * radius * 1.5f;
                    float z = patch.Y + Mathf.Sin(angle) * radius * .57f + SeabreezeWorld.Curve(x);
                    float scale = random.RandfRange(.76f, 1.18f) * (1.0f - .27f * radius);
                    var basis = new Basis(Vector3.Up, random.Randf() * Mathf.Tau).Scaled(Vector3.One * scale);
                    plants.Add(new(basis, new(x, world.HeightAt(x, z) - .04f, z)));
                }
            }
            CozyMeshBatches.Spatial(parent, flower, material, plants, "Verge hydrangeas", 16, 56, 5);
        }
    }

    private static Mesh BuildStem(RandomNumberGenerator random, Color bloom)
    {
        var mesh = new SurfaceTool();
        mesh.Begin(Mesh.PrimitiveType.Triangles);
        void Vertex(Vector3 position, Vector3 normal, Color pigment, Vector2? uv = null)
        {
            mesh.SetNormal(normal);
            mesh.SetUV(uv ?? new Vector2(0, -1));
            mesh.SetColor(pigment.SrgbToLinear());
            mesh.AddVertex(position);
        }

        float height = random.RandfRange(.95f, 1.25f);
        var head = new Vector3(.13f, height, .06f);
        var stalk = new Color("65754a");
        for (int i = 0; i < 6; i++)
        {
            Vector3 a = Vector3.Right.Rotated(Vector3.Up, i * Mathf.Tau / 6);
            Vector3 b = a.Rotated(Vector3.Up, Mathf.Tau / 6);
            Vertex(a * .012f, a, stalk); Vertex(head + a * .005f, a, stalk); Vertex(b * .012f, b, stalk);
            Vertex(b * .012f, b, stalk); Vertex(head + a * .005f, a, stalk); Vertex(head + b * .005f, b, stalk);
        }
        for (int i = 0; i < 8; i++)
        {
            var basePoint = head * (.25f + i / 2 * .18f);
            var axis = Vector3.Right.Rotated(Vector3.Up, i * Mathf.Pi + i / 2 * 1.7f);
            var side = axis.Cross(Vector3.Up);
            var green = new Color("377447").Lerp(new Color("60894e"), random.Randf());
            float length = random.RandfRange(.24f, .38f);
            for (int half = -1; half <= 1; half += 2)
            {
                void LeafPoint(int row, bool edge)
                {
                    float t = row / 12f;
                    float width = Mathf.Sin(t * Mathf.Pi) * length * (row % 2 == 0 ? .31f : .36f);
                    float rise = length * (.33f * Mathf.Sin(t * Mathf.Pi) - .16f * t);
                    var point = basePoint + axis * (t * length) + Vector3.Up * rise;
                    if (edge) point += side * (width * half) + Vector3.Up * width * .30f;
                    var normal = (Vector3.Up - side * half * .30f + axis * (t - .5f)).Normalized();
                    Vertex(point, normal, edge ? green.Darkened(.19f) : green.Lightened(.09f), new(edge ? half : 0, t));
                }
                for (int row = 0; row < 12; row++)
                {
                    LeafPoint(row, false); LeafPoint(row, true); LeafPoint(row + 1, false);
                    LeafPoint(row + 1, false); LeafPoint(row, true); LeafPoint(row + 1, true);
                }
            }
        }
        Vector2[] outline = [new(0, 0), new(.38f, -.37f), new(.79f, -.41f),
            new(1, -.14f), new(1, .14f), new(.79f, .41f), new(.38f, .37f)];
        float radius = random.RandfRange(.116f, .154f);
        for (int i = 0; i < 85; i++)
        {
            float y = 1.0f - (i + .5f) * 1.30f / 85;
            float angle = i * 2.39996f + random.RandfRange(-.055f, .055f);
            float ring = Mathf.Sqrt(1 - y * y);
            var outward = new Vector3(Mathf.Cos(angle) * ring, y, Mathf.Sin(angle) * ring);
            var center = head + outward * radius;
            var radial = outward.Cross(Vector3.Forward).Normalized().Rotated(outward, angle);
            var color = bloom.Lerp(new Color("dedbe9"), random.RandfRange(.02f, .56f));
            for (int petal = 0; petal < 4; petal++)
            {
                var axis = radial.Rotated(outward, petal * Mathf.Pi / 2);
                var side = axis.Cross(outward);
                float length = radius * random.RandfRange(.15f, .23f);
                var middle = center + axis * length * .56f;
                for (int j = 0; j < outline.Length; j++)
                {
                    Vertex(middle, outward, color.Lightened(.10f));
                    Edge(outline[j]);
                    Edge(outline[(j + 1) % outline.Length]);
                }
                void Edge(Vector2 point)
                {
                    var offset = axis * point.X + side * point.Y + outward * (point.X * .15f + Mathf.Abs(point.Y) * .32f);
                    Vertex(center + offset * length, outward, color.Darkened((1 - point.X) * .27f));
                }
            }
        }
        mesh.Index();
        return mesh.Commit();
    }
}
