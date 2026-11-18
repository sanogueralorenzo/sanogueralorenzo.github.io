using Godot;

namespace CozySora;

public sealed class SeabreezePlantMeshes
{
    private readonly SeabreezeRandom _rng;
    public SeabreezePlantMeshes(SeabreezeRandom random) => _rng = random;
    public sealed record Plant(ArrayMesh Leaves, float Radius, ArrayMesh? Trunk = null, ArrayMesh? CloseLeaves = null);
    public Vector3 Unit()
    {
        return new Vector3(_rng.RandfRange(-1, 1), _rng.RandfRange(-1, 1), _rng.RandfRange(-1, 1)).Normalized();
    }
    public Plant TreeMesh(int seed, bool tall, bool coastal = false)
    {
        uint saved = _rng.State;
        _rng.Seed = (uint)seed;
        float height = tall ? _rng.RandfRange(9.2f, 12.3f) : _rng.RandfRange(6.6f, 9.3f);
        float spread = _rng.RandfRange(2.5f, 4.0f);
        float radius = _rng.RandfRange(.24f, .37f);
        var wood = new SurfaceTool();
        var leaves = new SurfaceTool();
        wood.Begin(Mesh.PrimitiveType.Triangles);
        leaves.Begin(Mesh.PrimitiveType.Triangles);
        using var close = new SurfaceTool();
        close.Begin(Mesh.PrimitiveType.Triangles);
        var blades = new RandomNumberGenerator { Seed = (ulong)(81091 + seed * 19) };
        var crown = new Vector3(_rng.RandfRange(-.8f, .8f), height, _rng.RandfRange(-.8f, .8f));
        var bend = crown * .48f + Vector3.Right * _rng.RandfRange(-.43f, .43f);
        CurvedLimb(wood, Vector3.Zero, bend, crown, radius, .023f, 12, 8, 1.0f);
        for (int root = 0; root < 5; root++)
        {
            var direction = Vector3.Right.Rotated(Vector3.Up, root * 2.399963f + seed * .57f);
            var toe = direction * radius * _rng.RandfRange(1.55f, 2.7f);
            toe.Y = .08f;
            CurvedLimb(wood, Vector3.Up * _rng.RandfRange(.32f, .68f), toe * .34f + Vector3.Up * .1f,
                toe, radius * .4f, .016f, 7, 3);
        }

        const int limbs = 11;
        for (int limb = 0; limb < limbs; limb++)
        {
            float load = limb / (limbs - 1f);
            float station = Mathf.Lerp(.45f, .94f, load);
            float angle = limb * 2.399963f + seed * .41f + _rng.RandfRange(-.35f, .35f);
            var radial = Vector3.Right.Rotated(Vector3.Up, angle);
            var tangent = radial.Cross(Vector3.Up);
            var origin = Curve(Vector3.Zero, bend, crown, station);
            float reach = spread * _rng.RandfRange(.77f, 1.14f) * (1.14f - .66f * load);
            var tip = origin + radial * reach + Vector3.Up * height * _rng.RandfRange(.13f, .23f);
            var elbow = origin.Lerp(tip, .50f) - Vector3.Up * height * .065f + tangent * reach * .22f;
            float limbRadius = radius * (.53f - load * .27f);
            CurvedLimb(wood, origin, elbow, tip, limbRadius, .018f, 8, 5);
            for (int shoot = 0; shoot < 4; shoot++)
            {
                float along = .41f + shoot * .18f;
                var joint = Curve(origin, elbow, tip, along);
                var outward = (radial * .65f + tangent * (shoot % 2 == 0 ? -.72f : .72f)).Normalized();
                float size = _rng.RandfRange(.69f, 1.18f) * (1.12f - .27f * load);
                var end = joint + outward * size + Vector3.Up * size * _rng.RandfRange(.32f, .86f);
                CurvedLimb(wood, joint, joint.Lerp(end, .46f) + Vector3.Up * size * .16f, end,
                    limbRadius * .36f, .005f, 5, 3);
                for (int spray = 0; spray < 11; spray++)
                {
                    var offset = Unit();
                    offset.Y *= .68f;
                    var at = joint.Lerp(end, _rng.RandfRange(.65f, 1.09f)) + offset * size * .71f;
                    var normal = (Vector3.Up * .61f + offset * .46f + outward * .28f).Normalized();
                    var orientation = new Basis(new Quaternion(Vector3.Back, normal)).Rotated(normal, _rng.RandfRange(0, Mathf.Tau));
                    float width = size * _rng.RandfRange(.70f, 1.39f);
                    float light = _rng.RandfRange(.62f, 1.14f) * (.76f + along * .26f);
                    var color = new Color(light * _rng.RandfRange(.87f, 1.10f), light, light * .91f, along * .49f);
                    if (coastal && limb < 5)
                    {
                        LeafSpray(close, blades, at, orientation, width, color);
                        continue;
                    }
                    void LeafVertex(Vector2 uv, float ridge)
                    {
                        var point = new Vector3((uv.X - .5f) * width, (.5f - uv.Y) * width * .87f, ridge * width);
                        leaves.SetUV(uv);
                        leaves.SetNormal((normal + orientation.X * (.32f * (uv.X - .5f))).Normalized());
                        leaves.SetColor(color);
                        leaves.AddVertex(at + orientation * point);
                    }
                    if (limb < 5)
                        for (int edge = 0; edge < 4; edge++)
                        {
                            LeafVertex(CardCorners[(edge + 1) % 4], 0);
                            LeafVertex(CardCorners[edge], 0);
                            LeafVertex(new Vector2(.5f, .5f), .18f);
                        }
                    else
                        foreach (int corner in CardTriangles) LeafVertex(CardCorners[corner], 0);
                }
            }
        }
        wood.Index();
        var result = new Plant(leaves.Commit(), spread + 1.25f, wood.Commit(), coastal ? close.Commit() : null);
        _rng.State = saved;
        return result;
    }

    private static void LeafSpray(SurfaceTool mesh, RandomNumberGenerator rng, Vector3 center, Basis plane, float width, Color shade)
    {
        for (int blade = 0; blade < 19; blade++)
        {
            float angle = blade * 2.399963f + rng.RandfRange(-.22f, .22f);
            float distance = width * .54f * Mathf.Sqrt((blade + .5f) / 19f);
            var local = new Vector3(Mathf.Cos(angle) * distance, Mathf.Sin(angle) * distance * .72f,
                rng.RandfRange(-.16f, .16f) * width);
            var root = center + plane * local;
            var axis = (plane * new Vector3(Mathf.Cos(angle), Mathf.Sin(angle), rng.RandfRange(-.65f, .8f))).Normalized();
            var side = plane.Z.Cross(axis).Normalized();
            var normal = axis.Cross(side);
            float length = rng.RandfRange(.15f, .25f) * Mathf.Clamp(width, .72f, 1.2f);
            float halfWidth = length * rng.RandfRange(.23f, .32f);
            var color = new Color(shade.R * rng.RandfRange(.82f, 1.18f), shade.G * rng.RandfRange(.88f, 1.20f), shade.B, shade.A);
            void Vertex(float t, float across)
            {
                float outline = Mathf.Sin(t * Mathf.Pi) * halfWidth;
                var at = root + axis * (t * length) + side * (outline * across)
                    + normal * (length * (.16f * t * t + .05f * Mathf.Sin(t * Mathf.Pi) * (1 - Mathf.Abs(across))));
                mesh.SetColor(color);
                mesh.SetNormal((normal - axis * t * .24f + side * across * .27f).Normalized());
                mesh.SetUV(new((across + 1) * .5f, 1 - t));
                mesh.AddVertex(at);
            }
            for (int segment = 0; segment < 3; segment++)
                for (int vane = -1; vane < 1; vane++)
                {
                    float start = segment / 3f;
                    float end = (segment + 1) / 3f;
                    if (segment > 0)
                    {
                        Vertex(start, vane); Vertex(end, vane); Vertex(start, vane + 1);
                    }
                    if (segment < 2)
                    {
                        Vertex(start, vane + 1); Vertex(end, vane); Vertex(end, vane + 1);
                    }
                }
        }
    }

    private static readonly int[] CardTriangles = [0, 2, 1, 0, 3, 2];
    private static readonly Vector2[] CardCorners = [new(0, 1), new(1, 1), new(1, 0), new(0, 0)];

    private static Vector3 Curve(Vector3 start, Vector3 bend, Vector3 end, float t) =>
        start.Lerp(bend, t).Lerp(bend.Lerp(end, t), t);

    private static void CurvedLimb(SurfaceTool mesh, Vector3 start, Vector3 bend, Vector3 end, float baseRadius,
        float tipRadius, int sides, int sections, float flare = 0)
    {
        var direction = (end - start).Normalized();
        var reference = direction.Cross(Mathf.Abs(direction.X) < .79f ? Vector3.Right : Vector3.Up).Normalized();
        void Vertex(int row, int side)
        {
            float t = (float)row / sections;
            var tangent = ((bend - start) * (1 - t) + (end - bend) * t).Normalized();
            var across = tangent.Cross(reference).Normalized();
            var axis = across.Cross(tangent);
            float angle = side * Mathf.Tau / sides;
            var normal = axis * Mathf.Cos(angle) + across * Mathf.Sin(angle);
            float ribs = 1 + .10f * Mathf.Cos(angle * 3 + t * 3) + .07f * Mathf.Sin(angle * 5 - t * 5);
            float radius = Mathf.Lerp(tipRadius, baseRadius, Mathf.Pow(1 - t, 1.16f)) * ribs
                * (1 + flare * Mathf.Exp(-t * 22) * (.65f + .35f * Mathf.Cos(angle * 5)));
            mesh.SetNormal(normal);
            mesh.AddVertex(Curve(start, bend, end, t) + normal * radius);
        }
        for (int row = 0; row < sections; row++)
            for (int side = 0; side < sides; side++)
            {
                int next = (side + 1) % sides;
                Vertex(row, side);
                Vertex(row + 1, next);
                Vertex(row, next);
                Vertex(row, side);
                Vertex(row + 1, side);
                Vertex(row + 1, next);
            }
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
