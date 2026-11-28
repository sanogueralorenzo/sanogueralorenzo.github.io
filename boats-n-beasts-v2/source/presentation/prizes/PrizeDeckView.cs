using BoatsNBeasts.Core;
using Godot;
using N = System.Numerics.Vector2;

namespace BoatsNBeasts;

internal partial class PrizeDeckView : Node3D
{
    public PrizeBoarding Board = null!;
    public NativeStage3D Stage = null!;
    Node3D? floor, tool;
    Node3D player = null!, mate = null!, passenger = null!;
    readonly Dictionary<PrizeGuard, Node3D> guards = [];
    int room;
    public Vector2 Screen(N p, float height = .45f) => Stage.Screen(p * 100, height);
    public override void _Ready()
    {
        Stage = new(); AddChild(Stage); Stage.PaintWater(BluewaterCoast.Water(Board.Watch.Country.Climate));
        Stage.Follow(Vector2.Zero, 10.85f);
        player = ActorArt3D.BoardingParty(0); mate = ActorArt3D.BoardingParty(1); passenger = ActorArt3D.BoardingParty(2);
        Stage.AddChild(player); Stage.AddChild(mate); Stage.AddChild(passenger);
        Sync(0);
    }
    public void Sync(float clock)
    {
        Stage.Advance(clock);
        if (room != Board.Room)
        {
            room = Board.Room; floor?.QueueFree(); floor = PrizeArt.Deck(Board, Board.Watch.Country); Stage.AddChild(floor);
            tool?.QueueFree(); tool = PrizeArt.Prop(Board.Work switch { DeckWork.Signal => "winch", DeckWork.Pump => "pump", DeckWork.Chains => "winch", _ => "crate" }, Board.Watch.Country.Accent);
            Stage.AddChild(tool);
        }
        tool!.Visible = !Board.Fixed && Board.Work is not (DeckWork.Search or DeckWork.Captain); tool.Position = PrizeArt.OnDeck(Board.WorkPoint);
        player.Position = PrizeArt.OnDeck(Board.Player); player.Rotation = new(0, -MathF.Atan2(Board.Facing.X, -Board.Facing.Y), Board.Roll > 0 ? MathF.Sin(Board.Roll * 11) * .22f : 0);
        mate.Position = PrizeArt.OnDeck(Board.Mate); var dir = Board.Player - Board.Mate; mate.Rotation = new(0, -MathF.Atan2(dir.X, -dir.Y), 0);
        passenger.Visible = Board.PassengerFree; passenger.Position = PrizeArt.OnDeck(Board.Passenger);
        foreach (var old in guards.Keys.Where(g => g.Health <= 0 || !Board.Guards.Contains(g)).ToArray()) { guards[old].QueueFree(); guards.Remove(old); }
        foreach (var g in Board.Guards)
        {
            if (g.Health <= 0) continue;
            if (!guards.TryGetValue(g, out var actor))
            {
                actor = ActorArt3D.BoardingParty(g.Role == 3 ? 0 : g.Role == 2 ? 2 : 1);
                var dye = g.Role == 3 ? new Color("b94d49") : g.Role == 2 ? new Color("745080") : new Color("b97041");
                var crest = new ActorGeometry(); crest.Sphere(new(0, .92f, 0), new(.19f, .11f, .16f), dye);
                crest.Tube([new(-.09f, .92f, .09f), new(-.19f, .99f, .14f), new(-.24f, 1.04f, .19f)], [.045f, .042f, .011f], new("f3c885"));
                actor.AddChild(new MeshInstance3D { Mesh = crest.Mesh(DioramaSurface.Material) }); if (g.Role == 3) actor.Scale = Vector3.One * 1.15f;
                Stage.AddChild(actor); guards.Add(g, actor);
            }
            actor.Position = PrizeArt.OnDeck(g.Position);
            var facing = g.Tell > 0 || g.Dash > 0 ? g.Aim : Board.Player - g.Position;
            actor.Rotation = new(g.Stun > 0 ? .18f : 0, -MathF.Atan2(facing.X, -facing.Y), g.Tell > 0 ? -.13f : 0);
        }
    }
}
