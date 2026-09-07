using Godot;

namespace CozySora;

public partial class HarborTransit : Node3D
{
    private HarborWorld _map = null!;
    private Node3D car = null!, van = null!;
    private readonly List<Node3D> birds = new();
    private double time, routeTime;
    private AudioStreamPlayer3D bells = null!;
    private bool profiling;
    public void Build(HarborWorld world)
    {
        _map = world;
        profiling = OS.GetCmdlineUserArgs().Contains("--profile");
        car = new Node3D();
        car.Name = "Bay and Hill cable car";
        AddChild(car);
        var geometry = new HarborGeometry(car, true);
        geometry.Box(new Vector3(0, .55f, 0), new Vector3(2.25f, .38f, 6.3f), "756f52", true);
        geometry.Box(new Vector3(0, 1.2f, 0), new Vector3(2.1f, .9f, 3.2f), "a57353", true);
        geometry.Box(new Vector3(0, 2.75f, 0), new Vector3(2.55f, .22f, 6.7f), "59736b");
        geometry.Box(new Vector3(0, 2.91f, 0), new Vector3(2.1f, .14f, 4.4f), "687970");
        foreach (var side in new[] { -1, 1 })
        {
            foreach (var z in new[] { -2.6f, -1.4f, 0, 1.4f, 2.6f })
            {
                geometry.Beam(new Vector3(side * 1.0f, .7f, z), new Vector3(side * 1.0f, 2.7f, z), .055f, "ddc696");
            }
            foreach (var z in new[] { -1.0f, 0, 1.0f })
            {
                geometry.Box(new Vector3(side * 1.07f, 2.03f, z), new Vector3(.035f, .91f, .85f), "8ca5a0");
            }
            geometry.Box(new Vector3(side * .7f, .91f, 2.3f), new Vector3(.46f, .15f, 1.3f), "a9946a");
            geometry.Box(new Vector3(side * 1.01f, 1.24f, 2.3f), new Vector3(.09f, .65f, 1.4f), "a9946a");
            foreach (var z in new[] { -2.0f, 2.0f })
            {
                geometry.Add("cylinder", new Vector3(side * .95f, .36f, z), new Vector3(.57f, .24f, .57f), "424e4c", new Vector3(0, 0, Mathf.Pi * .5f));
            }
        }
        foreach (var side in new[] { -1, 1 })
        {
            geometry.Box(new Vector3(0, 1.17f, side * 3.0f), new Vector3(2.18f, .6f, .15f), "a57353");
            geometry.Box(new Vector3(0, .58f, side * 3.28f), new Vector3(1.9f, .13f, .5f), "697166");
            geometry.Label("BAY & HILL", new Vector3(0, 2.49f, side * 3.08f), 1.6f, "f3dfb0", (side == 1 ? 0 : Mathf.Pi));
            geometry.Add("sphere", new Vector3(0, 1.3f, side * 3.12f), new Vector3(.25f, .25f, .12f), "efdeb1");
        }
        // Cream window frames, timber panels, running boards and destination fascia.
        foreach (var side in new[] { -1, 1 })
        {
            foreach (var z in new[] { -1.0f, 0, 1.0f })
            {
                foreach (var edge in new[] { -.46f, .46f })
                {
                    geometry.Box(new Vector3(side * 1.105f, 2.03f, z + edge), new Vector3(.08f, 1.07f, .055f), "e0cfa5");
                }
                foreach (var y in new[] { 1.53f, 2.51f })
                {
                    geometry.Box(new Vector3(side * 1.11f, y, z), new Vector3(.09f, .065f, .96f), "e0cfa5");
                }
                geometry.Box(new Vector3(side * 1.13f, 2.2f, z - .27f), new Vector3(.03f, .51f, .11f), "c0d2c8");
            }
            for (int z = 0; z < 13; z += 1)
            {
                geometry.Box(new Vector3(side * 1.065f, 1.2f, -1.45f + z * .24f), new Vector3(.035f, .71f, .025f), "cfad78");
            }
            geometry.Box(new Vector3(side * 1.13f, 1.59f, 0), new Vector3(.18f, .12f, 3.35f), "ddc18b");
            geometry.Box(new Vector3(side * 1.23f, .58f, 0), new Vector3(.34f, .12f, 5.7f), "a48b60");
            geometry.Box(new Vector3(side * 1.2f, .35f, 2.43f), new Vector3(.49f, .12f, 1.35f), "606b60", true);
            geometry.Box(new Vector3(side * 1.2f, .35f, -2.43f), new Vector3(.49f, .12f, 1.35f), "606b60", true);
            geometry.Box(new Vector3(side * 1.29f, 2.72f, 0), new Vector3(.07f, .28f, 6.65f), "c4ac7a");
            geometry.Box(new Vector3(side * 1.34f, 2.73f, 0), new Vector3(.06f, .24f, 2.9f), "597168");
            geometry.Label("BAY & HILL · 07", new Vector3(side * 1.378f, 2.73f, 0), 2.6f, "f2dfb3", side * Mathf.Pi * .5f);
            foreach (var z in new[] { -2.65f, 2.65f })
            {
                geometry.Beam(new Vector3(side * .94f, .75f, z), new Vector3(side * .94f, 2.4f, z), .035f, "c6b584");
                geometry.Box(new Vector3(side * .68f, .91f, z), new Vector3(.47f, .13f, .74f), "b19b6f");
                for (int slat = 0; slat < 3; slat += 1)
                {
                    geometry.Box(new Vector3(side * .99f, 1.1f + slat * .15f, z), new Vector3(.055f, .08f, .79f), "b8a174");
                }
            }
            foreach (var end in new[] { -1, 1 })
            {
                geometry.Beam(new Vector3(side * .93f, 1.1f, end * 3.02f), new Vector3(side * .93f, 2.1f, end * 3.02f), .037f, "d3bd8c");
                geometry.Beam(new Vector3(side * .35f, 1.54f, end * 3.04f), new Vector3(side * .92f, 1.54f, end * 3.04f), .035f, "d3bd8c");
            }
            foreach (var z in new[] { -2.0f, 2.0f })
            {
                geometry.Box(new Vector3(side * .84f, .33f, z), new Vector3(.24f, .27f, 1.03f), "3f514d");
                geometry.Add("cylinder", new Vector3(side * 1.09f, .36f, z), new Vector3(.24f, .045f, .24f), "b0ac8c", new Vector3(0, 0, Mathf.Pi * .5f));
            }
        }
        foreach (var end in new[] { -1, 1 })
        {
            geometry.Box(new Vector3(0, 2.43f, end * 3.13f), new Vector3(1.86f, .34f, .1f), "526d60");
            geometry.Label("BAY & HILL", new Vector3(0, 2.43f, end * 3.2f), 1.65f, "f3dfb0", (end == 1 ? 0 : Mathf.Pi));
            geometry.Box(new Vector3(0, .42f, end * 3.4f), new Vector3(1.35f, .18f, .17f), "414e49");
            foreach (var side in new[] { -1, 1 })
            {
                geometry.Add("sphere", new Vector3(side * .73f, 1.33f, end * 3.11f), new Vector3(.3f, .3f, .2f), "d3ba84");
                geometry.Add("sphere", new Vector3(side * .73f, 1.33f, end * 3.22f), new Vector3(.2f, .2f, .08f), "f3e6b4");
            }
        }
        geometry.Label("07", new Vector3(0, 1.22f, 3.09f), .42f, "f3dfb0");
        geometry.Finish();
        BuildBell();
        van = new Node3D();
        van.Name = "Morning delivery";
        AddChild(van);
        geometry = new HarborGeometry(van, true);
        geometry.Box(new Vector3(0, .9f, 0), new Vector3(1.8f, 1.4f, 4.0f), "b6ba9e", true);
        geometry.Box(new Vector3(0, 1.3f, -1.9f), new Vector3(1.6f, .65f, .04f), "6d9195");
        foreach (var side in new[] { -1, 1 })
        {
            foreach (var z in new[] { -1.2f, 1.2f })
            {
                geometry.Add("cylinder", new Vector3(side * .9f, .38f, z), new Vector3(.65f, .2f, .65f), "424e4c", new Vector3(0, 0, Mathf.Pi * .5f));
            }
        }
        geometry.Finish();
        for (int i = 0; i < 15; i += 1)
        {
            var bird = new Node3D();
            AddChild(bird);
            birds.Add(bird);
            var mesh = new ArrayMesh();
            var st = new SurfaceTool();
            st.Begin(Mesh.PrimitiveType.Triangles);
            foreach (var v in new[] { new Vector3(0, 0, .3f), new Vector3(-.65f, .06f, -.08f), new Vector3(0, 0, -.2f), new Vector3(0, 0, -.2f), new Vector3(.65f, .06f, -.08f), new Vector3(0, 0, .3f) })
            {
                st.AddVertex(v);
            }
            st.GenerateNormals();
            mesh = st.Commit();
            var n = new MeshInstance3D();
            n.Mesh = mesh;
            var material = new StandardMaterial3D();
            material.AlbedoColor = new Color("dfdfcf");
            material.CullMode = BaseMaterial3D.CullModeEnum.Disabled;
            n.MaterialOverride = material;
            bird.AddChild(n);
        }
        UpdatePositions();
    }
    private void BuildBell()
    {
        bells = new AudioStreamPlayer3D { Name = "Cable car bell", MaxDistance = 48, UnitSize = 7, VolumeDb = -17 };
        car.AddChild(bells);
        var bytes = new byte[22050 * 2];
        for (int i = 0; i < 22050; i++)
        {
            double t = i / 22050.0;
            double sample = (Math.Sin(Math.Tau * 1174 * t) * .55 + Math.Sin(Math.Tau * 2354 * t) * .25 + Math.Sin(Math.Tau * 3281 * t) * .12) * Math.Exp(-t * 6) * Math.Min(1, t * 80);
            System.Buffers.Binary.BinaryPrimitives.WriteInt16LittleEndian(bytes.AsSpan(i * 2, 2), (short)(sample * 22000));
        }
        bells.Stream = new AudioStreamWav { Format = AudioStreamWav.FormatEnum.Format16Bits, MixRate = 22050, Data = bytes };
    }

    public override void _PhysicsProcess(double delta)
    {
        time += delta;
        routeTime += delta;
        UpdatePositions();
        if ((int)(time / 23) != (int)((time - delta) / 23))
        {
            bells.Play();
            if (profiling) GD.Print("Harbor Hills BELL route_time=", routeTime, " position=", car.Position);
        }
        if (profiling && (int)(routeTime / 20) != (int)((routeTime - delta) / 20))
            GD.Print("Harbor Hills TRANSIT route_time=", routeTime, " position=", car.Position, " rotation=", car.RotationDegrees);
    }

    public void SetPaused(bool value)
    {
        if (IsInstanceValid(bells)) bells.StreamPaused = value;
    }

    private void UpdatePositions()
    {
        float cycle = (float)(routeTime % 160);
        bool northbound = cycle < 80;
        float leg = cycle % 80;
        float[] stops = northbound ? [-100, -32, 46, 96] : [96, 46, -32, -100];
        float z = leg switch
        {
            < 6 => stops[0],
            < 30 => Mathf.Lerp(stops[0], stops[1], (leg - 6) / 24),
            < 35 => stops[1],
            < 61 => Mathf.Lerp(stops[1], stops[2], (leg - 35) / 26),
            < 66 => stops[2],
            < 76 => Mathf.Lerp(stops[2], stops[3], (leg - 66) / 10),
            _ => stops[3]
        };
        car.Position = _map.Point(8, z, .05f);
        float grade = Mathf.Atan2(_map.HeightAt(8, z + 1) - _map.HeightAt(8, z - 1), 2);
        float yaw = northbound ? 0 : Mathf.Pi;
        if (leg > 76) yaw += Mathf.Pi * Mathf.SmoothStep(76, 80, leg);
        // Turn around the grade normal so the wheels stay on the rail.
        car.Basis = new Basis(Vector3.Right, -grade) * new Basis(Vector3.Up, yaw);
        double phase = time * .044;
        float x = 90 + 2.4f * (float)Math.Sin(phase), vanZ = 14 - 112 * (float)Math.Cos(phase);
        var tangent = new Vector2(2.4f * (float)Math.Cos(phase), 112 * (float)Math.Sin(phase)).Normalized();
        float slope = (_map.HeightAt(x + tangent.X, vanZ + tangent.Y) - _map.HeightAt(x - tangent.X, vanZ - tangent.Y)) * .5f;
        van.Position = _map.Point(x, vanZ, .12f);
        van.LookAt(van.Position + new Vector3(tangent.X, slope, tangent.Y), Vector3.Up);
        for (int i = 0; i < birds.Count; i++)
        {
            double angle = time * (.08 + i * .002) + i * .73;
            birds[i].Position = new((float)Math.Cos(angle) * 65 - 25, 18 + (float)Math.Sin(angle * .7) * 5 + i * .6f, -151 + (float)Math.Sin(angle) * 22);
            birds[i].Rotation = new(0, -(float)angle + Mathf.Pi * .5f, (float)Math.Sin(angle * .8) * .2f);
        }
    }
}
