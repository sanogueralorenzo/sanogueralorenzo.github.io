using Godot;
namespace BoatsNBeasts;

// Two reusable triangle batches keep the number of draw calls independent of trail length.
internal sealed class EffectsGeometry
{
    readonly ImmediateMesh mesh = new();
    readonly StandardMaterial3D material;
    bool started;
    public EffectsGeometry(Node3D owner, bool translucent)
    {
        material = new StandardMaterial3D
        {
            VertexColorUseAsAlbedo = true,
            VertexColorIsSrgb = true,
            ShadingMode = translucent ? BaseMaterial3D.ShadingModeEnum.Unshaded : BaseMaterial3D.ShadingModeEnum.PerPixel,
            Transparency = translucent ? BaseMaterial3D.TransparencyEnum.Alpha : BaseMaterial3D.TransparencyEnum.Disabled,
            CullMode = BaseMaterial3D.CullModeEnum.Disabled, Roughness = .92f,
        };
        owner.AddChild(new MeshInstance3D { Mesh = mesh, CastShadow = GeometryInstance3D.ShadowCastingSetting.Off });
    }
    public void Begin() { mesh.ClearSurfaces(); started = false; }
    public void End() { if (started) mesh.SurfaceEnd(); }
    public void Triangle(Vector3 a, Vector3 b, Vector3 c, Color color)
    {
        var cross = (b - a).Cross(c - a);
        if (cross.LengthSquared() < 1e-14f) return;
        if (!started) { mesh.SurfaceBegin(Mesh.PrimitiveType.Triangles, material); started = true; }
        var normal = cross.Normalized();
        mesh.SurfaceSetColor(color); mesh.SurfaceSetNormal(normal);
        mesh.SurfaceAddVertex(a); mesh.SurfaceAddVertex(b); mesh.SurfaceAddVertex(c);
    }
    public void Ribbon(Vector3 a, Vector3 b, float wa, float wb, Color color)
    {
        var d = b - a; d.Y = 0;
        if (d.LengthSquared() < .000001f) return;
        var n = new Vector3(-d.Z, 0, d.X).Normalized();
        Triangle(a + n * wa, b + n * wb, b - n * wb, color);
        Triangle(a + n * wa, b - n * wb, a - n * wa, color);
    }
    public void Arc(Vector3 center, float radius, float start, float length, float width, Color color, int segments = 18)
    {
        var last = center + new Vector3(Mathf.Cos(start), 0, Mathf.Sin(start)) * radius;
        for (int i = 1; i <= segments; i++)
        {
            float angle = start + length * i / segments;
            var next = center + new Vector3(Mathf.Cos(angle), 0, Mathf.Sin(angle)) * radius;
            Ribbon(last, next, width, width, color); last = next;
        }
    }

    public static StandardMaterial3D Matte(string color) => new() { AlbedoColor = new Color(color), Roughness = .9f };
    public static MeshInstance3D Part(Node3D root, Mesh mesh, Material material, Vector3 at, Vector3 scale, Vector3 rotation = default)
    {
        var part = new MeshInstance3D { Mesh = mesh, MaterialOverride = material, Position = at, Scale = scale, Rotation = rotation };
        root.AddChild(part); return part;
    }
    // A beveled box rather than a box primitive: shared by planks, chest body and metal straps.
    public static ArrayMesh BeveledBox(float bevel = .1f)
    {
        var st = new SurfaceTool(); st.Begin(Mesh.PrimitiveType.Triangles);
        Vector3[] axes = [Vector3.Right, Vector3.Up, Vector3.Back];
        void Face(Vector3[] p)
        {
            for (int i = 1; i < p.Length - 1; i++)
            {
                var n = (p[i] - p[0]).Cross(p[i + 1] - p[0]).Normalized(); st.SetNormal(n);
                st.AddVertex(p[0]); st.AddVertex(p[i + 1]); st.AddVertex(p[i]);
            }
        }
        float h = .5f, q = h - bevel;
        for (int axis = 0; axis < 3; axis++) for (int sign = -1; sign <= 1; sign += 2)
        {
            var n = axes[axis] * sign; var u = axes[(axis + 1) % 3]; var v = axes[(axis + 2) % 3] * sign;
            Face([n*h-u*q-v*q,n*h+u*q-v*q,n*h+u*q+v*q,n*h-u*q+v*q]);
        }
        for (int axis = 0; axis < 3; axis++) for (int a = -1; a <= 1; a += 2) for (int b = -1; b <= 1; b += 2)
        {
            var u = axes[(axis+1)%3]*a; var v = axes[(axis+2)%3]*b; var n = axes[axis];
            Vector3[] p = [u*h+v*q-n*q,u*q+v*h-n*q,u*q+v*h+n*q,u*h+v*q+n*q];
            if ((p[1]-p[0]).Cross(p[2]-p[0]).Dot(u+v)<0) Array.Reverse(p);
            Face(p);
        }
        for (int x = -1; x <= 1; x += 2) for (int y = -1; y <= 1; y += 2) for (int z = -1; z <= 1; z += 2)
        {
            Vector3[] p = [new(x*h,y*q,z*q),new(x*q,y*h,z*q),new(x*q,y*q,z*h)];
            if ((p[1]-p[0]).Cross(p[2]-p[0]).Dot(new Vector3(x,y,z))<0) Array.Reverse(p);
            Face(p);
        }
        return st.Commit();
    }
}
