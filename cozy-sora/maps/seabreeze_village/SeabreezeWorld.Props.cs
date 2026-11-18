using Godot;

namespace CozySora;

public partial class SeabreezeWorld
{
    private void Wire(Vector3 a, Vector3 b, float sag)
    {
        var previous = a;
        for (int i = 1; i < 21; i += 1)
        {
            var t = i / 20.0f;
            var point = a.Lerp(b, t) - Vector3.Up * Mathf.Sin(t * Mathf.Pi) * sag;
            CozyPrimitives.Beam(this, previous, point, .021f, Palette.Color("5c636a"));
            previous = point;
        }
    }
    private void Guardrail(List<Vector2> points)
    {
        Vector2[] profile = [new(.00f, .00f), new(.014f, .021f), new(.069f, .063f),
            new(.069f, .091f), new(.016f, .145f), new(.016f, .165f), new(.069f, .219f),
            new(.069f, .247f), new(.014f, .289f), new(.00f, .31f)];
        var steel = new ShaderMaterial { Shader = GD.Load<Shader>("res://maps/seabreeze_village/guardrail.gdshader") };
        var hardware = new StandardMaterial3D { AlbedoColor = new("9ca4a5"), Metallic = .77f, Roughness = .47f };
        var bolts = new List<Transform3D>();
        var strip = new SurfaceTool();
        strip.Begin(Mesh.PrimitiveType.Triangles);
        var collision = new StaticBody3D();
        AddChild(collision);
        float along = 0;
        for (int i = 0; i < points.Count; i++)
        {
            var p = new Vector3(points[i].X, HeightAt(points[i].X, points[i].Y), points[i].Y);
            CozyPrimitives.Cylinder(this, p + Vector3.Up * .46f, .074f, .074f, .92f, hardware);
            CozyCollision.Box(collision, p + Vector3.Up * .46f, new(.15f, .92f, .15f));
            if (i == 0) continue;
            var last = points[i - 1];
            var a = new Vector3(last.X, HeightAt(last.X, last.Y), last.Y);
            var side = (p - a).Cross(Vector3.Up).Normalized();
            float length = a.DistanceTo(p);
            for (int fold = 1; fold < profile.Length; fold++)
            {
                var lower = profile[fold - 1];
                var upper = profile[fold];
                var normal = (side * (upper.Y - lower.Y) - Vector3.Up * (upper.X - lower.X)).Normalized();
                void Vertex(Vector3 post, Vector2 section, float distance)
                {
                    strip.SetNormal(normal);
                    strip.SetUV(new(distance, section.Y));
                    strip.AddVertex(post + side * (.075f + section.X) + Vector3.Up * (.56f + section.Y));
                }
                Vertex(a, lower, along); Vertex(a, upper, along); Vertex(p, lower, along + length);
                Vertex(p, lower, along + length); Vertex(a, upper, along); Vertex(p, upper, along + length);
            }
            var rotation = Basis.LookingAt(p - a, Vector3.Up);
            CozyCollision.Box(collision, (a + p) * .5f + Vector3.Up * .7f, new(.14f, .7f, length), rotation.GetEuler());
            foreach (float height in new[] { .635f, .791f })
                bolts.Add(new(new Basis(new Quaternion(Vector3.Up, side)), p + Vector3.Up * height + side * .15f));
            along += length;
        }
        CozyPrimitives.Instance(this, strip.Commit(), Vector3.Zero, steel);
        CozyMeshBatches.Spatial(this, CozyPrimitives.CylinderMesh(.019f, .017f, .012f, 6), hardware, bolts, "Rail fasteners", 24);
    }
    private void Sign(Vector3 pos, string text, string color, Vector2 size, float yaw = 0)
    {
        var sign_root = new Node3D();
        AddChild(sign_root);
        sign_root.Position = pos;
        sign_root.Rotation = new Vector3(0, yaw, 0);
        CozyPrimitives.Cylinder(sign_root, new Vector3(0, .65f, 0), .035f, .035f, 1.3f, Palette.Color("828986"));
        CozyPrimitives.Box(sign_root, new Vector3(0, 1.3f, 0), new Vector3(size.X, size.Y, .045f), Palette.Color(color));
        if (text == ">>")
        {
            foreach (var dx in new[] { -size.X * .22f, size.X * .19f })
            {
                foreach (var side in new[] { -1, 1 })
                {
                    var bar = CozyPrimitives.Box(sign_root, new Vector3(dx, 1.3f + side * size.Y * .14f, .028f), new Vector3(size.X * .29f, .055f, .008f), Palette.Color("343b3c"));
                    bar.Rotation = new Vector3(0, 0, -side * .65f);
                }
            }
        }
        else
        {
            var label = new Label3D();
            label.Text = text;
            label.FontSize = 64;
            label.PixelSize = .005f;
            label.Modulate = new Color("343b3c");
            label.Position = new Vector3(0, 1.3f, .03f);
            sign_root.AddChild(label);
        }
    }
    private void BuildCoastProps()
    {
        var points = new List<Vector2>();
        for (int i = 0; i < 7; i += 1)
        {
            points.Add(new Vector2(-9.35f, 6.5f - i * 2));
        }
        for (int i = 0; i < 13; i += 1)
        {
            float x = -10.2f - i * 3;
            points.Add(new Vector2(x, -7.5f + Curve(x)));
        }
        Guardrail(points);
        points = new List<Vector2>();
        for (int x = -60; x < 37; x += 3)
        {
            points.Add(new Vector2(x, -17.5f + Curve(x)));
        }
        Guardrail(points);
        var concrete = new ShaderMaterial { Shader = GD.Load<Shader>("res://maps/seabreeze_village/pole.gdshader") };
        var collar = new StandardMaterial3D { AlbedoColor = new("636768"), Metallic = .68f, Roughness = .49f };
        var porcelain = new StandardMaterial3D { AlbedoColor = new("d8d9c7"), Roughness = .23f };
        var tops = new List<Vector3>();
        foreach (var p in new[] { new Vector2(-34, -6.3f + Curve(-34)), new Vector2(-10.5f, -17.3f + Curve(-10.5f)), new Vector2(16, -17.3f + Curve(16)), new Vector2(42, -17.3f + Curve(42)), new Vector2(64, -17.3f + Curve(64)) })
        {
            var y = HeightAt(p.X, p.Y);
            CozyPrimitives.Cylinder(this, new Vector3(p.X, y + 5, p.Y), .19f, .12f, 10.5f, concrete);
            foreach (float height in new[] { 2.32f, 2.73f, 7.15f, 8.86f })
            {
                float radius = .19f - height / 10.5f * .07f + .006f;
                CozyPrimitives.Cylinder(this, new(p.X, y + height, p.Y), radius, radius, .042f, collar);
            }
            CozyPrimitives.Box(this, new Vector3(p.X, y + 9, p.Y), new Vector3(2, .12f, .18f), Palette.Color("5c6358"));
            foreach (var dx in new[] { -.85f, 0, .85f })
            {
                CozyPrimitives.Cylinder(this, new(p.X + dx, y + 9.2f, p.Y), .043f, .043f, .3f, porcelain);
                for (int rib = 0; rib < 3; rib++)
                    CozyPrimitives.Cylinder(this, new(p.X + dx, y + 9.13f + rib * .065f, p.Y), .091f, .054f, .045f, porcelain);
            }
            tops.Add(new Vector3(p.X, y + 9.35f, p.Y));
            CozyCollision.StaticBox(this, new Vector3(p.X, y + 5, p.Y), new Vector3(.35f, 10, .35f));
        }
        for (int i = 0; i < tops.Count - 1; i += 1)
        {
            foreach (var dx in new[] { -.85f, 0, .85f })
            {
                Wire(tops[i] + new Vector3(dx, 0, 0), tops[i + 1] + new Vector3(dx, 0, 0), 1);
            }
            Wire(tops[i] - Vector3.Up * 2, tops[i + 1] - Vector3.Up * 2, 1.2f);
        }
        float gantry_z = -18 + Curve(8);
        var ground = HeightAt(8, gantry_z);
        foreach (var x in new[] { 7.4f, 8.6f })
        {
            CozyPrimitives.Cylinder(this, new Vector3(x, ground + 5.1f, gantry_z), .16f, .13f, 10.5f, concrete);
        }
        foreach (var y in new[] { 6.9f, 9.8f })
        {
            CozyPrimitives.Box(this, new Vector3(8, ground + y, gantry_z), new Vector3(1.4f, .12f, .16f), Palette.Color("5c6358"));
        }
        CozyPrimitives.Box(this, new Vector3(8, ground + 6.5f, gantry_z), new Vector3(.85f, .9f, .14f), Palette.Color("dadac8"));
        foreach (var x in new[] { 7.4f, 8.6f })
        {
            Wire(new Vector3(x, ground + 10, gantry_z), tops[2], .3f);
        }
        Sign(new Vector3(-8.75f, HeightAt(-8.75f, 3.2f), 3.2f), ">>", "ddd879", new Vector2(.5f, .38f));
        Sign(new Vector3(-1, HeightAt(-1, -17.05f), -17.05f), ">>", "e5d478", new Vector2(.85f, .58f), -.95f);
        Sign(new Vector3(40, HeightAt(40, -17.1f + Curve(40)), -17.1f + Curve(40)), ">>", "e5d478", new Vector2(.8f, .55f), -1.35f);
        Sign(new Vector3(-12.5f, HeightAt(-12.5f, -17.2f + Curve(-12.5f)), -17.2f + Curve(-12.5f)), "↗", "e5c063", new Vector2(.7f, .7f));
        Sign(new Vector3(24, HeightAt(24, -17.2f + Curve(24)), -17.2f + Curve(24)), "40", "efe5d6", new Vector2(.8f, .8f));
        // Parked olive kei car, 4.6m length, with distinct dark roof and glass cabin.
        var car = new Node3D();
        AddChild(car);
        car.Position = new Vector3(21.5f, HeightAt(21.5f, -14.2f + Curve(21.5f)), -14.2f + Curve(21.5f));
        car.Rotation = new Vector3(0, .08f, 0);
        CozyPrimitives.Box(car, new Vector3(0, .62f, 0), new Vector3(4.6f, .62f, 1.65f), Palette.Color("70867e"), true);
        CozyPrimitives.Box(car, new Vector3(0, 1.2f, 0), new Vector3(2.55f, .65f, 1.5f), Palette.Color("26394a"));
        CozyPrimitives.Box(car, new Vector3(0, 1.56f, 0), new Vector3(2.7f, .12f, 1.65f), Palette.Color("3a3d44"));
        foreach (var x in new[] { -1.5f, 1.5f })
        {
            foreach (var z in new[] { -.82f, .82f })
            {
                var wheel = CozyPrimitives.Cylinder(car, new Vector3(x, .37f, z), .36f, .36f, .2f, Palette.Color("1c1c1c"));
                wheel.Rotation = new Vector3(Mathf.Pi / 2, 0, 0);
            }
        }
        foreach (var z in new[] { -.56f, .56f })
        {
            CozyPrimitives.Box(car, new Vector3(-2.31f, .74f, z), new Vector3(.045f, .2f, .32f), Palette.Color("c83332"));
        }
    }
}
