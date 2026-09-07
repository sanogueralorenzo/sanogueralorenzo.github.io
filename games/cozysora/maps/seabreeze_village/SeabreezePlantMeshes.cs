using Godot;

namespace CozySora;

public sealed class SeabreezePlantMeshes
{
    private readonly SeabreezeRandom _rng;
    public SeabreezePlantMeshes(SeabreezeRandom random) => _rng = random;
    public sealed record Plant(ArrayMesh Leaves, float Radius, ArrayMesh? Trunk = null);
    public Vector3 Unit()
    {
        return new Vector3(_rng.RandfRange(-1, 1), _rng.RandfRange(-1, 1), _rng.RandfRange(-1, 1)).Normalized();
    }
    public Plant TreeMesh(int seed_value, bool tall)
    {
        uint saved = _rng.State;
        _rng.Seed = (uint)seed_value;
        float h = (tall ? _rng.RandfRange(7, 11) : _rng.RandfRange(4.5f, 7.5f));
        var radii = new Vector3(_rng.RandfRange(2.4f, 4.2f), _rng.RandfRange(2, 3.4f), _rng.RandfRange(2.4f, 4.2f));
        var center = new Vector3(0, h + radii.Y * 0.35f, 0);
        var leaves = Canopy(center, radii, _rng.RandiRange(6, 9), _rng.RandiRange(52, 69), 7, _rng.RandfRange(1.2f, 1.6f), _rng.RandfRange(0.9f, 1.3f), h * 0.5f, h + radii.Y * 1.6f);
        var trunk = new SurfaceTool();
        trunk.Begin(Mesh.PrimitiveType.Triangles);
        float trunk_h = h + radii.Y * 0.2f;
        float radius = _rng.RandfRange(0.22f, 0.36f);
        TaperedBranch(trunk, Vector3.Zero, new Vector3(0, trunk_h, 0), radius, radius * 0.55f, 9);
        for (int j = 0; j < 4; j += 1)
        {
            var end = new Vector3(_rng.RandfRange(-0.6f, 0.6f) * radii.X, h + radii.Y * _rng.RandfRange(0.1f, 0.7f), _rng.RandfRange(-0.6f, 0.6f) * radii.Z);
            TaperedBranch(trunk, new Vector3(0, trunk_h, 0), end, radius * 0.36f, radius * 0.16f, 6);
        }
        trunk.GenerateNormals();
        var result = new Plant(leaves, Mathf.Max(radii.X, radii.Z) + 1, trunk.Commit());
        _rng.State = saved;
        return result;
    }
    public Plant BushMesh(int kind)
    {
        uint saved = _rng.State;
        _rng.Seed = (uint)new[] { 21, 22, 23, 31, 41, 42, 43 }[kind];
        var radii = ((kind < 3 ? new Vector3(_rng.RandfRange(1.2f, 2.4f), _rng.RandfRange(0.9f, 1.7f), _rng.RandfRange(1.2f, 2.4f)) : Vector3.One));
        int clusters = 0;
        float size = 0;
        if (kind == 3)
        {
            radii = new Vector3(1.6f, 1.5f, 1.6f);
            clusters = 40;
            size = 0.75f;
        }
        else if (kind >= 4)
        {
            radii = new[] { new Vector3(2.6f, 1.9f, 2.4f), new Vector3(2.2f, 2.3f, 2.2f), new Vector3(3, 1.6f, 2.6f) }[kind - 4];
            clusters = new[] { 70, 64, 76 }[kind - 4];
            size = new[] { 0.78f, 0.72f, 0.8f }[kind - 4];
        }
        int lobes = _rng.RandiRange(5, 7);
        if (kind < 3)
        {
            clusters = _rng.RandiRange(18, 27);
            size = _rng.RandfRange(0.85f, 1.15f);
        }
        var leaves = Canopy(new Vector3(0, radii.Y * 0.75f, 0), radii, lobes, clusters, 6, size, _rng.RandfRange(0.55f, 0.85f), 0, radii.Y * 2, (kind is 2 or 5 ? "gold" : ((kind == 3 ? "cool" : "green"))));
        _rng.State = saved;
        return new Plant(leaves, Mathf.Max(radii.X, radii.Z));
    }
    public ArrayMesh Canopy(Vector3 center, Vector3 radii, int lobes, int clusters, int cards, float card_size, float cluster_radius, float sway_base, float sway_top, string tint_kind = "green")
    {
        var st = new SurfaceTool();
        st.Begin(Mesh.PrimitiveType.Triangles);
        var centers = new List<Vector3>();
        for (int i = 0; i < lobes; i += 1)
        {
            float phi = (float)_rng.Randf() * Mathf.Tau;
            float y = _rng.RandfRange(-1, 1);
            centers.Add((center + new Vector3(Mathf.Sqrt(1 - y * y) * Mathf.Cos(phi), y, Mathf.Sqrt(1 - y * y) * Mathf.Sin(phi)) * radii * 0.7f + new Vector3(0, radii.Y * 0.1f, 0)));
        }
        for (int i = 0; i < clusters; i += 1)
        {
            Vector3 cluster = (centers[_rng.RandiRange(0, centers.Count - 1)] + Unit() * Mathf.Pow((float)_rng.Randf(), 0.6f) * cluster_radius * 1.6f);
            Color tint;
            if (tint_kind == "gold")
            {
                tint = new Color(_rng.RandfRange(1.1f, 1.6f), _rng.RandfRange(1, 1.25f), _rng.RandfRange(0.45f, 0.75f));
            }
            else if (tint_kind == "cool")
            {
                tint = new Color(_rng.RandfRange(0.7f, 1), _rng.RandfRange(0.85f, 1.1f), _rng.RandfRange(0.85f, 1.15f));
            }
            else
            {
                tint = new Color(_rng.RandfRange(0.85f, 1.3f), _rng.RandfRange(0.9f, 1.15f), _rng.RandfRange(0.75f, 1.05f));
            }
            float shade = (0.72f + 0.28f * Mathf.Min(1, ((cluster - center) / radii).Length())) * _rng.RandfRange(0.62f, 1.34f);
            Color color = tint * shade;
            for (int j = 0; j < cards; j += 1)
            {
                Vector3 p = cluster + Unit() * Mathf.Pow((float)_rng.Randf(), 0.7f) * cluster_radius;
                Vector3 radial = ((p - center) / (radii * radii)).Normalized();
                Vector3 outward = (p - cluster).Normalized().Lerp(radial, 0.72f).Normalized();
                Vector3 normal = ((outward + new Vector3(_rng.RandfRange(-0.6f, 0.6f), _rng.RandfRange(-0.6f, 0.6f), _rng.RandfRange(-0.6f, 0.6f))).Normalized());
                if ((float)_rng.Randf() < 0.25f)
                {
                    normal = Unit();
                }
                var basis = new Basis(new Quaternion(Vector3.Back, normal)).Rotated(normal, (float)_rng.Randf() * Mathf.Tau);
                float size = card_size * _rng.RandfRange(0.75f, 1.25f);
                var points = new[] { new Vector3(-0.5f, -0.5f, 0), new Vector3(0.5f, -0.5f, 0), new Vector3(0.5f, 0.5f, 0), new Vector3(-0.5f, 0.5f, 0) };
                var uvs = new[] { new Vector2(0, 1), new Vector2(1, 1), new Vector2(1, 0), new Vector2(0, 0) };
                var weights = new List<float>();
                for (int corner = 0; corner < 4; corner += 1)
                {
                    weights.Add(Mathf.Clamp((p.Y - sway_base) / (sway_top - sway_base), 0, 1) * _rng.RandfRange(0.6f, 1));
                }
                foreach (var k in new[] { 0, 2, 1, 0, 3, 2 })
                {
                    Vector3 vertex = p + basis * points[k] * size;
                    st.SetUV(uvs[k]);
                    st.SetNormal(outward.Lerp(((vertex - center) / (radii * radii)).Normalized(), 0.35f).Normalized());
                    color.A = weights[k];
                    st.SetColor(color);
                    st.AddVertex(vertex);
                }
            }
        }
        return st.Commit();
    }
    public void TaperedBranch(SurfaceTool st, Vector3 start, Vector3 end, float radius, float tip, int segments)
    {
        Vector3 direction = (end - start).Normalized();
        Vector3 side = direction.Cross(Vector3.Forward).Normalized();
        if (side.Length() < 0.1f)
        {
            side = Vector3.Right;
        }
        Vector3 other = direction.Cross(side).Normalized();
        for (int i = 0; i < segments; i += 1)
        {
            float a = (float)(i) / segments * Mathf.Tau;
            float b = (float)(i + 1) / segments * Mathf.Tau;
            Vector3 radial_a = side * Mathf.Cos(a) + other * Mathf.Sin(a);
            Vector3 radial_b = side * Mathf.Cos(b) + other * Mathf.Sin(b);
            var points = new[] { start + radial_a * radius, start + radial_b * radius, end + radial_b * tip, end + radial_a * tip };
            foreach (var k in new[] { 0, 2, 1, 0, 3, 2 })
            {
                st.SetUV(new Vector2((float)(i) / segments, (k < 2 ? 0 : 1)));
                st.AddVertex(points[k]);
            }
        }
    }
    public ArrayMesh GrassMesh()
    {
        var st = new SurfaceTool();
        st.Begin(Mesh.PrimitiveType.Triangles);
        for (int blade = 0; blade < 3; blade += 1)
        {
            float angle = blade * Mathf.Tau / 3 + (float)_rng.Randf() * 0.8f;
            var basis = new Basis(Vector3.Up, angle);
            float width = _rng.RandfRange(0.1f, 0.15f);
            float bend = _rng.RandfRange(0.2f, 0.6f);
            var offset = new Vector3(_rng.RandfRange(-0.06f, 0.06f), 0, _rng.RandfRange(-0.06f, 0.06f));
            for (int segment = 0; segment < 4; segment += 1)
            {
                foreach (var k in new[] { 0, 2, 1, 1, 2, 3 })
                {
                    float t = (float)(segment + k / 2) / 4;
                    float sign_x = (k % 2 == 0 ? -1 : 1);
                    st.SetUV(new Vector2((sign_x < 0 ? 0 : 1), t));
                    st.SetNormal(basis * new Vector3(0, 0.3f, 1).Normalized());
                    st.SetColor(Colors.White);
                    st.AddVertex((offset + basis * new Vector3(sign_x * width * Mathf.Pow(1 - t, .7f) * 0.42f, t * (1f - blade * .13f), bend * t * t)));
                }
            }
        }
        return st.Commit();
    }
    public ArrayMesh PineTier(Vector3 center, float radius, float tree_height)
    {
        var st = new SurfaceTool();
        st.Begin(Mesh.PrimitiveType.Triangles);
        for (int i = 0; i < Mathf.CeilToInt(radius * radius * 7) + 12; i += 1)
        {
            float angle = (float)_rng.Randf() * Mathf.Tau;
            float distance = Mathf.Sqrt((float)_rng.Randf()) * radius;
            float fraction = distance / radius;
            var p = (center + new Vector3(Mathf.Cos(angle) * distance, 0.14f * radius * (1 - fraction * fraction) + _rng.RandfRange(-0.2f, 0.2f), Mathf.Sin(angle) * distance));
            float size = _rng.RandfRange(1, 1.5f);
            float pitch = 0.35f + fraction * 0.55f + _rng.RandfRange(-0.2f, 0.2f);
            var basis = (new Basis(Vector3.Up, Mathf.Pi * 0.5f - angle) * new Basis(Vector3.Right, -(Mathf.Pi * 0.5f - pitch)) * new Basis(Vector3.Back, _rng.RandfRange(-0.4f, 0.4f)));
            var normal = new Vector3(Mathf.Cos(angle) * 0.6f, 1, Mathf.Sin(angle) * 0.6f).Normalized();
            float shade = _rng.RandfRange(0.72f, 1.12f) * (0.78f + 0.22f * fraction);
            var color = new Color(shade * 0.9f, shade, shade * 0.95f, 0.3f + center.Y / tree_height * 0.35f + 0.25f * fraction);
            foreach (var k in new[] { 0, 2, 1, 0, 3, 2 })
            {
                Vector2 uv = new[] { new Vector2(0, 1), new Vector2(1, 1), new Vector2(1, 0), new Vector2(0, 0) }[k];
                st.SetUV(uv);
                st.SetNormal(normal);
                st.SetColor(color);
                st.AddVertex(p + basis * new Vector3((uv.X - 0.5f) * size, (0.5f - uv.Y) * size * 0.8f, 0));
            }
        }
        return st.Commit();
    }
}
