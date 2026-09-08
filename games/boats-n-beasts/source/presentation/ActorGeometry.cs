using Godot;
using System;
using System.Collections.Generic;

namespace BoatsNBeasts;

/// <summary>Small triangle collector with explicit smooth normals and vertex colors.</summary>
internal sealed class ActorGeometry
{
    readonly List<Vector3> vertices = new(), normals = new();
    readonly List<Color> colors = new();
    void Triangle(Vector3 a, Vector3 b, Vector3 c, Vector3 na, Vector3 nb, Vector3 nc, Color color)
    {
        // Godot uses clockwise front faces. Normals are supplied independently of winding.
        if ((b - a).Cross(c - a).Dot(na + nb + nc) > 0) { (b, c) = (c, b); (nb, nc) = (nc, nb); }
        vertices.Add(a); vertices.Add(b); vertices.Add(c);
        normals.Add(na); normals.Add(nb); normals.Add(nc);
        colors.Add(color); colors.Add(color); colors.Add(color);
    }
    void Quad(Vector3 a, Vector3 b, Vector3 c, Vector3 d, Vector3 na, Vector3 nb, Vector3 nc, Vector3 nd, Color color)
    {
        Triangle(a, b, c, na, nb, nc, color); Triangle(a, c, d, na, nc, nd, color);
    }
    public void Scale(Vector3 scale)
    {
        for (int i = 0; i < vertices.Count; i++)
        {
            vertices[i] *= scale;
            normals[i] = (normals[i] / scale).Normalized();
        }
    }
    public ArrayMesh Mesh(Material material)
    {
        var arrays = new Godot.Collections.Array(); arrays.Resize((int)Godot.Mesh.ArrayType.Max);
        arrays[(int)Godot.Mesh.ArrayType.Vertex] = vertices.ToArray();
        arrays[(int)Godot.Mesh.ArrayType.Normal] = normals.ToArray();
        arrays[(int)Godot.Mesh.ArrayType.Color] = colors.ToArray();
        var mesh = new ArrayMesh(); mesh.AddSurfaceFromArrays(Godot.Mesh.PrimitiveType.Triangles, arrays);
        mesh.SurfaceSetMaterial(0, material); return mesh;
    }
    public void Sphere(Vector3 p, Vector3 radius, Color color, int segments = 16, int rings = 10)
    {
        Vector3 N(int x, int y)
        {
            float a = x * Mathf.Tau / segments, h = y * Mathf.Pi / rings;
            return new(MathF.Sin(h) * MathF.Cos(a), MathF.Cos(h), MathF.Sin(h) * MathF.Sin(a));
        }
        for (int y = 0; y < rings; y++) for (int x = 0; x < segments; x++)
        {
            var a = N(x, y); var b = N(x + 1, y); var c = N(x + 1, y + 1); var d = N(x, y + 1);
            Quad(p + a * radius, p + b * radius, p + c * radius, p + d * radius,
                (a / radius).Normalized(), (b / radius).Normalized(), (c / radius).Normalized(), (d / radius).Normalized(), color);
        }
    }
    public void RoundBox(Vector3 p, Vector3 size, float bevel, Color color)
    {
        var half = size * .5f; bevel = MathF.Min(bevel, MathF.Min(half.X, MathF.Min(half.Y, half.Z)) * .95f);
        const int steps = 4;
        foreach (var axis in new[] { Vector3.Right, Vector3.Left, Vector3.Up, Vector3.Down, Vector3.Forward, Vector3.Back })
        {
            var u = MathF.Abs(axis.Y) > .5f ? Vector3.Right : Vector3.Up;
            var v = axis.Cross(u);
            (Vector3 p, Vector3 n) Point(int x, int y)
            {
                // Edge samples follow the bevel rather than wasting vertices on flat face centers.
                float C(int i, float h) => i switch { 0 => -h, 1 => -h + bevel, 2 => 0, 3 => h - bevel, _ => h };
                float hu = u.Abs().Dot(half), hv = v.Abs().Dot(half);
                Vector3 cube = axis * axis.Abs().Dot(half) + u * C(x, hu) + v * C(y, hv);
                var inner = half - Vector3.One * bevel;
                var clamp = new Vector3(Math.Clamp(cube.X, -inner.X, inner.X), Math.Clamp(cube.Y, -inner.Y, inner.Y), Math.Clamp(cube.Z, -inner.Z, inner.Z));
                var n = (cube - clamp).Normalized(); return (p + clamp + n * bevel, n);
            }
            for (int y = 0; y < steps; y++) for (int x = 0; x < steps; x++)
            {
                var a = Point(x, y); var b = Point(x + 1, y); var c = Point(x + 1, y + 1); var d = Point(x, y + 1);
                Quad(a.p, b.p, c.p, d.p, a.n, b.n, c.n, d.n, color);
            }
        }
    }
    public void Polygon(Vector3[] points, Color color, Vector3 normal)
    {
        var center = Vector3.Zero; foreach (var p in points) center += p; center /= points.Length;
        for (int i = 0; i < points.Length; i++) Triangle(center, points[i], points[(i + 1) % points.Length], normal, normal, normal, color);
    }
    public void Loft(Vector3[][] rings, Color[] bandColors)
    {
        for (int j = 0; j < rings.Length - 1; j++) for (int i = 0; i < rings[j].Length; i++)
        {
            int next = (i + 1) % rings[j].Length;
            var a = rings[j][i]; var b = rings[j][next]; var c = rings[j + 1][next]; var d = rings[j + 1][i];
            var n = (b - a).Cross(d - a).Normalized();
            var outward = new Vector3((a.X + b.X + c.X + d.X) * .25f, 0, (a.Z + b.Z + c.Z + d.Z) * .25f);
            if (n.Dot(outward) < 0) n = -n;
            Quad(a, b, c, d, n, n, n, n, bandColors[Math.Min(j, bandColors.Length - 1)]);
        }
    }
    public void Tube(Vector3[] path, float radius, Color color, int sides = 8) => Tube(path, System.Linq.Enumerable.Repeat(radius, path.Length).ToArray(), color, sides);
    public void Tube(Vector3[] path, float[] radii, Color color, int sides = 8)
    {
        // Catmull-Rom joints create soft legs, necks and rails without separate sphere draws.
        var centers = new List<Vector3>(); var widths = new List<float>();
        int steps = path.Length > 2 ? 4 : 1;
        for (int i = 0; i < path.Length - 1; i++) for (int k = 0; k < steps; k++)
        {
            float t = k / (float)steps;
            Vector3 a = path[Math.Max(0, i - 1)], b = path[i], c = path[i + 1], d = path[Math.Min(path.Length - 1, i + 2)];
            centers.Add((2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t * t * t) * .5f);
            widths.Add(Mathf.Lerp(radii[i], radii[i + 1], t));
        }
        centers.Add(path[^1]); widths.Add(radii[^1]);
        var rings = new Vector3[centers.Count][]; var ns = new Vector3[centers.Count][];
        Vector3 previousU = Vector3.Zero;
        for (int i = 0; i < centers.Count; i++)
        {
            var tangent = (centers[Math.Min(i + 1, centers.Count - 1)] - centers[Math.Max(0, i - 1)]).Normalized();
            var u = previousU == Vector3.Zero ? tangent.Cross(MathF.Abs(tangent.Y) > .92f ? Vector3.Right : Vector3.Up).Normalized()
                : (previousU - tangent * tangent.Dot(previousU)).Normalized();
            if (u.LengthSquared() < .1f) u = tangent.Cross(Vector3.Right).Normalized();
            previousU = u; var v = tangent.Cross(u).Normalized();
            rings[i] = new Vector3[sides]; ns[i] = new Vector3[sides];
            for (int k = 0; k < sides; k++)
            {
                float a = k * Mathf.Tau / sides; var n = u * MathF.Cos(a) + v * MathF.Sin(a);
                rings[i][k] = centers[i] + n * widths[i]; ns[i][k] = n;
            }
        }
        for (int i = 0; i < centers.Count - 1; i++) for (int k = 0; k < sides; k++)
        {
            int next = (k + 1) % sides;
            Quad(rings[i][k], rings[i][next], rings[i + 1][next], rings[i + 1][k], ns[i][k], ns[i][next], ns[i + 1][next], ns[i + 1][k], color);
        }
        Polygon(rings[0], color, (centers[0] - centers[1]).Normalized());
        Polygon(rings[^1], color, (centers[^1] - centers[^2]).Normalized());
    }
    public void ClosedTube(Vector3[] path, float radius, Color color, int sides = 8)
    {
        // Each corner is capped by a rounded joint; all pieces still become one mesh surface.
        for (int i = 0; i < path.Length; i++)
        {
            Tube(new[] { path[i], path[(i + 1) % path.Length] }, radius, color, sides);
            Sphere(path[i], Vector3.One * radius, color, sides, 5);
        }
    }
    public void Ring(Vector3 p, float radius, float thickness, Color color)
    {
        const int n = 24;
        var points = new Vector3[n + 1];
        for (int i = 0; i <= n; i++) { float a = i * Mathf.Tau / n; points[i] = p + new Vector3(MathF.Cos(a) * radius, 0, MathF.Sin(a) * radius); }
        Tube(points, thickness, color, 7);
    }
    public void Crystal(Vector3 p, Vector3 size, Color color)
    {
        const int n = 6; var middle = new Vector3[n];
        for (int i = 0; i < n; i++) { float a = i * Mathf.Tau / n; middle[i] = p + new Vector3(MathF.Cos(a) * size.X, -.18f * size.Y, MathF.Sin(a) * size.Z); }
        for (int i = 0; i < n; i++)
        {
            var a = middle[i]; var b = middle[(i + 1) % n];
            var top = p + Vector3.Up * size.Y; var bottom = p - Vector3.Up * size.Y * .65f;
            var normal = (b - a).Cross(top - a).Normalized(); if (normal.Dot((a + b) * .5f - p) < 0) normal = -normal;
            var tint = color.Lightened(i % 3 * .055f);
            Triangle(a, b, top, normal, normal, normal, tint);
            normal = (b - a).Cross(bottom - a).Normalized(); if (normal.Dot((a + b) * .5f - p) < 0) normal = -normal;
            Triangle(a, b, bottom, normal, normal, normal, color.Darkened(.12f));
        }
    }
}
