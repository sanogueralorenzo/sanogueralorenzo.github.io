using Godot;

namespace CozySora;

public static class CozyGrassMesh
{
    public static ArrayMesh Create(ulong seed, int bladeCount, float maximumWidth)
    {
        var random = new RandomNumberGenerator { Seed = seed };
        var mesh = new SurfaceTool();
        mesh.Begin(Mesh.PrimitiveType.Triangles);
        for (int blade = 0; blade < bladeCount; blade++)
        {
            float angle = blade * 2.399963f + random.RandfRange(-.28f, .28f);
            var forward = new Vector3(Mathf.Sin(angle), 0, Mathf.Cos(angle));
            var side = Vector3.Up.Cross(forward);
            var basePoint = forward * random.RandfRange(.02f, .14f) + side * random.RandfRange(-.085f, .085f);
            float height = random.RandfRange(.47f, 1f);
            float width = maximumWidth * random.RandfRange(.46f, 1f);
            float lean = random.RandfRange(.10f, .33f);
            float curl = random.RandfRange(-.18f, .18f);
            float straw = blade == bladeCount - 1 ? .75f : random.RandfRange(.02f, .29f);
            float shade = random.RandfRange(.82f, 1.16f);
            int sections = blade % 2 == 0 ? 3 : 2;

            void Vertex(int row, int edge)
            {
                float t = (float)row / sections;
                float halfWidth = width * .5f * (1 - t) * (1 + .85f * t);
                var axis = side.Rotated(forward, curl * t);
                var position = basePoint + Vector3.Up * (t * height) + forward * (t * t * lean)
                    + axis * (edge * halfWidth) + side * (curl * t * t);
                var normal = (forward - Vector3.Up * (2 * t * lean / height)).Normalized();
                mesh.SetColor(new Color(shade, straw, 1));
                mesh.SetNormal(normal);
                mesh.SetUV(new Vector2((edge + 1) * .5f, t));
                mesh.AddVertex(position);
            }
            for (int row = 0; row < sections; row++)
            {
                Vertex(row, -1);
                Vertex(row + 1, -1);
                Vertex(row, 1);
                if (row == sections - 1) continue;
                Vertex(row, 1);
                Vertex(row + 1, -1);
                Vertex(row + 1, 1);
            }
        }
        mesh.Index();
        return mesh.Commit();
    }
}
