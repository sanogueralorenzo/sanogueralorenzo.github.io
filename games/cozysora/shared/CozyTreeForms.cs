using Godot;

namespace CozySora;

/// <summary>Procedural woody forms. Map generators retain planting and species ownership.</summary>
public static class CozyTreeForms
{
    // A continuous buttressed collar, not separate poles. Outer lobes disappear
    // below the sampled soil; the upper rings blend back into the living trunk.
    public static ArrayMesh RootFlare(Vector3 center, float radius, float reach, float height,
        float phase, Func<float, float, float> ground, Vector3 lean = default)
    {
        const int sides = 64, rings = 10;
        var surface = new SurfaceTool();
        surface.Begin(Mesh.PrimitiveType.Triangles);
        Vector3 Point(int ring, int side)
        {
            float t = (float)ring / rings, a = (float)side / sides * Mathf.Tau;
            float lobe = Mathf.Pow(Mathf.Max(0, Mathf.Cos(a * 5 + phase + .18f * Mathf.Sin(a * 3))), 5);
            float r = radius * (1 - .12f * t) + (reach - radius) * (.16f + .84f * lobe) * Mathf.Pow(1 - t, 3.4f);
            var p = center + new Vector3(Mathf.Cos(a) * r, 0, Mathf.Sin(a) * r) + lean * t;
            p.Y = Mathf.Lerp(ground(p.X, p.Z) - .09f, center.Y + height, Mathf.Pow(t, .83f));
            return p;
        }
        for (int ring = 0; ring < rings; ring++)
            for (int side = 0; side < sides; side++)
                foreach (int k in new[] { 0, 1, 2, 1, 3, 2 })
                {
                    int y = ring + k / 2, x = side + k % 2;
                    surface.SetUV(new((float)x / sides, (float)y / rings));
                    surface.AddVertex(Point(y, x));
                }
        surface.GenerateNormals();
        return surface.Commit();
    }

    // Reusable gently irregular, unit-height tapered limb.
    public static ArrayMesh Limb(float tip)
    {
        const int sides = 12, rings = 6;
        var surface = new SurfaceTool();
        surface.Begin(Mesh.PrimitiveType.Triangles);
        for (int ring = 0; ring < rings; ring++)
            for (int side = 0; side < sides; side++)
                foreach (int k in new[] { 0, 1, 2, 1, 3, 2 })
                {
                    float t = (float)(ring + k / 2) / rings;
                    float a = (float)(side + k % 2) / sides * Mathf.Tau;
                    float r = Mathf.Lerp(.5f, tip, t) * (1 + .055f * Mathf.Sin(a * 3 + t * 2));
                    surface.SetUV(new((float)(side + k % 2) / sides, t));
                    surface.AddVertex(new(Mathf.Cos(a) * r + .045f * Mathf.Sin(t * Mathf.Pi), t - .5f, Mathf.Sin(a) * r));
                }
        surface.GenerateNormals();
        return surface.Commit();
    }
}
