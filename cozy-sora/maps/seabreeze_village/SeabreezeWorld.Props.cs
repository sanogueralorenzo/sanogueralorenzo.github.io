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
        var previous = Vector3.Zero;
        for (int i = 0; i < points.Count; i += 1)
        {
            var p = new Vector3(points[i].X, HeightAt(points[i].X, points[i].Y), points[i].Y);
            CozyPrimitives.Box(this, p + new Vector3(0, .5f, 0), new Vector3(.12f, 1, .12f), Palette.Color("828986"), true);
            if (i > 0)
            {
                var a = previous + Vector3.Up * .7f;
                var b = p + Vector3.Up * .7f;
                var n = CozyPrimitives.Box(this, (a + b) / 2, new Vector3(.1f, .25f, a.DistanceTo(b)), Palette.Color("a3a9a4"));
                n.LookAtFromPosition((a + b) / 2, b);
                // The low guardrail has a matching collision ribbon.
                CozyCollision.StaticBox(n, Vector3.Zero, new Vector3(.14f, .7f, a.DistanceTo(b)));
            }
            previous = p;
        }
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
        var tops = new List<Vector3>();
        foreach (var p in new[] { new Vector2(-34, -6.3f + Curve(-34)), new Vector2(-10.5f, -17.3f + Curve(-10.5f)), new Vector2(16, -17.3f + Curve(16)), new Vector2(42, -17.3f + Curve(42)), new Vector2(64, -17.3f + Curve(64)) })
        {
            var y = HeightAt(p.X, p.Y);
            CozyPrimitives.Cylinder(this, new Vector3(p.X, y + 5, p.Y), .19f, .12f, 10.5f, Palette.Color("9c9478"));
            CozyPrimitives.Box(this, new Vector3(p.X, y + 9, p.Y), new Vector3(2, .12f, .18f), Palette.Color("5c6358"));
            foreach (var dx in new[] { -.85f, 0, .85f })
            {
                CozyPrimitives.Cylinder(this, new Vector3(p.X + dx, y + 9.2f, p.Y), .085f, .08f, .3f, Palette.Color("d9d9c8"));
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
            CozyPrimitives.Cylinder(this, new Vector3(x, ground + 5.1f, gantry_z), .16f, .13f, 10.5f, Palette.Color("9c9478"));
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
