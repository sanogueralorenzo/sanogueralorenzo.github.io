using Godot;
using BoatsNBeasts.Core;
namespace BoatsNBeasts;

// Separate native art proof, never constructs or changes a gameplay Voyage.
public partial class ArtSample : Node3D
{
    NativeStage3D stage = null!;
    float clock;
    bool close;
    public override void _Ready()
    {
        stage = new(); AddChild(stage);
        var island = EnvironmentArt3D.Build(new Place("sample", PlaceKind.Harbor, default, 140, 147));
        AddChild(island); island.Position = new(-3.2f, 0, -1.4f);
        var rocky = EnvironmentArt3D.Build(new Place("sample-rock", PlaceKind.Island, default, 155, 921));
        AddChild(rocky); rocky.Position = new(4, 0, .4f);
        var boat = ActorArt3D.Boat(BoatKind.Mage, [0,0,0,0,0,1]);
        AddChild(boat); boat.Rotation = new(0, -.7f, 0);
        var crab = ActorArt3D.Creature(EnemyKind.Crab); AddChild(crab); crab.Position = new(-2,0,1.6f); crab.Rotation = new(0,2.2f,0);
        GetWindow().Title = "Boats ’n’ Beasts · Native art sample";
    }
    public override void _Process(double delta) { clock += (float)delta; stage.Follow(Vector2.Zero, close ? 6.2f : 0); stage.Advance(clock); }
    public override async void _UnhandledKeyInput(InputEvent ev)
    {
        if (ev is not InputEventKey { Pressed: true, Echo: false } key) return;
        if (key.Keycode == Key.Tab) close = !close;
        if (key.Keycode == Key.F12)
        {
            await ToSignal(RenderingServer.Singleton, RenderingServer.SignalName.FramePostDraw);
            var folder = ProjectSettings.GlobalizePath("res://evidence");
            var file = folder + "/diorama-sample-" + (close ? "detail" : "scale") + ".png";
            GetViewport().GetTexture().GetImage().SavePng(file);
            GD.Print($"ART SAMPLE {file} renderer={RenderingServer.GetCurrentRenderingMethod()} fps={Engine.GetFramesPerSecond()} draws={Performance.GetMonitor(Performance.Monitor.RenderTotalDrawCallsInFrame)}");
        }
    }
}
