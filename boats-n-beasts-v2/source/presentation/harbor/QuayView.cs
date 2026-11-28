using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

internal enum WharfStop { Crew, Galley, Berth, Belfry }

internal partial class QuayView : Node3D
{
    internal HarborLedger Ledger = new();
    internal Action<WharfStop>? Arrived;
    internal bool Exploring = true;
    static readonly Vector2[] Stations = [new(-.87f, 1.82f), new(-2.31f, 2.26f), new(2.23f, 3.83f), new(1.14f, 1.61f)];
    readonly Node3D[] companions = new Node3D[2];
    NativeStage3D stage = null!;
    Node3D boat = null!, captain = null!;
    Vector2 position = new(.77f, 2.58f);
    WharfStop? destination;
    float clock;

    internal IEnumerable<WharfStop> OpenStations => Enum.GetValues<WharfStop>().Where(stop => stop != WharfStop.Belfry || Ledger.BellReleased);
    public override void _Ready()
    {
        stage = new(); AddChild(stage);
        AddChild(EnvironmentArt3D.HomePort(Ledger));
        boat = ActorArt3D.Boat(BoatKind.Cutter, [1, 0, 0, 0, 0, 0]);
        boat.Position = new(3.77f, 0, 4.72f);
        boat.Rotation = new(0,-.46f,0);
        AddChild(boat);
        var reef = EnvironmentArt3D.Build(new Place("breakwater",PlaceKind.Rock, default, 111, 197));
        reef.Position = new(6.55f,0,-2.60f);
        AddChild(reef);
        captain = ActorArt3D.LandingParty(0);
        captain.Scale = Vector3.One * 1.18f; captain.RotationDegrees = new(0, -138, 0);
        AddChild(captain);
        for (int i = 0; i < 2; i++)
        {
            companions[i] = ActorArt3D.LandingParty(i+1);
            companions[i].Position = i == 0 ? new(-1.38f,.21f,1.43f) : new(-.08f,.21f,1.95f);
            companions[i].Rotation = new(0, i == 0 ? -2.1f : 1.81f, 0);
            companions[i].Scale = Vector3.One * 1.18f; AddChild(companions[i]);
        }
        if (Ledger.BellReleased)
        {
            var keeper = ActorArt3D.NellSpindle();
            keeper.Position = new(.83f,.24f,.99f);
            keeper.RotationDegrees = new(0,-124,0);
            AddChild(keeper);
        }
        if (Ledger.Dedicated)
        {
            var guest = ActorArt3D.Visitor(Visitors.At(Ledger.Campaign));
            guest.Position = new(-1.46f,.24f,.64f);
            guest.RotationDegrees = new(0,-145,0);
            AddChild(guest);
        }
        Frame();
        PoseCaptain();
    }
    void Frame() => stage.Follow(new(35, 28), 9.9f);
    void PoseCaptain() => captain.Position = new(position.X, position.X < 1.8f && position.Y < 2.80f ? .243f : .202f, position.Y);
    internal Vector2 Marker(WharfStop stop)
    {
        var spot = Stations[(int)stop];
        return stage.Lens.UnprojectPosition(new(spot.X, .18f, spot.Y)) + new Vector2(0, 22);
    }
    internal void WalkTo(WharfStop stop) => destination = stop;
    internal void Hail() => Arrived?.Invoke(OpenStations.MinBy(stop => position.DistanceSquaredTo(Stations[(int)stop])));
    public override void _Process(double delta)
    {
        float dt = (float)Math.Min(.10, delta);
        clock += dt;
        Frame(); stage.Advance(clock);
        ActorArt3D.AnimateBoat(boat, clock, 0, 0);
        if (!Exploring) return;
        var move = new Vector2(
            (Input.IsPhysicalKeyPressed(Key.D) || Input.IsPhysicalKeyPressed(Key.Right) ? 1 : 0) - (Input.IsPhysicalKeyPressed(Key.A) || Input.IsPhysicalKeyPressed(Key.Left) ? 1 : 0),
            (Input.IsPhysicalKeyPressed(Key.S) || Input.IsPhysicalKeyPressed(Key.Down) ? 1 : 0) - (Input.IsPhysicalKeyPressed(Key.W) || Input.IsPhysicalKeyPressed(Key.Up) ? 1 : 0)).Normalized();
        if (move != Vector2.Zero) destination = null;
        if (destination is WharfStop target)
        {
            var offset = Stations[(int)target] - position;
            if (offset.Length() < .10f) { destination = null; Arrived?.Invoke(target); return; }
            move = offset.Normalized();
        }
        if (move == Vector2.Zero) return;
        var next = position + move * (2.76f * dt);
        float quayEdge = 2.88f + .95f * Mathf.SmoothStep(.85f, 2f, next.X);
        position = new(Mathf.Clamp(next.X,-2.93f,2.62f), Mathf.Clamp(next.Y,1.52f,quayEdge + .14f));
        PoseCaptain();
        captain.Position += Vector3.Up * (.034f * Mathf.Abs(Mathf.Sin(clock * 12)));
        captain.Rotation = new(0, Mathf.Atan2(-move.X,-move.Y), 0);
    }
}
