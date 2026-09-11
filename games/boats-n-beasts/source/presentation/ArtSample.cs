using Godot;
using BoatsNBeasts.Core;
namespace BoatsNBeasts;

// Separate native art proof, never constructs or changes a gameplay Voyage.
public partial class ArtSample : Node3D
{
    NativeStage3D stage = null!;
    float clock;
    bool close;
    float detailSize = 6.2f;
    bool beachReference = true;
    const string SettingsPath = "user://art-preview.cfg";
    Label status = null!;
    Node3D rocky = null!;
    Node3D home = null!, boat = null!, crab = null!;
    int islandStyle;
    int islandSize = 1;
    uint variant;
    // Fixed production seeds cover the eight coastline families.
    static readonly uint[] IslandStyles = [4, 6, 1, 2, 12, 32, 33, 34, 29, 5];
    static readonly float[] IslandSizes = [95, 200, 330, OceanWorld.MaxIslandRadius];
    public override void _Ready()
    {
        var settings = new ConfigFile();
        if (settings.Load(SettingsPath) == Error.Ok)
        {
            close = (bool)settings.GetValue("preview", "close", false);
            beachReference = (bool)settings.GetValue("preview", "reference", true);
            islandStyle = Math.Clamp((int)settings.GetValue("preview", "style", 0), 0, IslandStyles.Length - 1);
            islandSize = Math.Clamp((int)settings.GetValue("preview", "size", 1), 0, IslandSizes.Length - 1);
            variant = (uint)(long)settings.GetValue("preview", "variant", 0L);
        }
        stage = new(); AddChild(stage);
        home = EnvironmentArt3D.Build(new Place("sample", PlaceKind.Harbor, default, 140, 147));
        AddChild(home); home.Position = new(-3.2f, 0, -1.4f);
        boat = ActorArt3D.Boat(BoatKind.Mage, [0,0,0,0,0,1]);
        AddChild(boat); boat.Rotation = new(0, -.7f, 0);
        crab = ActorArt3D.Creature(EnemyKind.Crab); AddChild(crab); crab.Position = new(-2,0,1.6f); crab.Rotation = new(0,2.2f,0);
        var overlay = new CanvasLayer(); AddChild(overlay);
        status = new Label { Position = new(16, 12), MouseFilter = Control.MouseFilterEnum.Ignore };
        status.AddThemeColorOverride("font_color", new Color("fff0d6"));
        status.AddThemeColorOverride("font_shadow_color", new Color("123b48"));
        status.AddThemeConstantOverride("shadow_offset_x", 1);
        status.AddThemeConstantOverride("shadow_offset_y", 1);
        overlay.AddChild(status);
        ShowIsland();
        GetWindow().Title = "Boats ’n’ Beasts · Native art sample";
    }
    public override void _Process(double delta)
    {
        clock += (float)delta;
        var center = close ? new Vector2(rocky.Position.X, rocky.Position.Z) * 100 : Vector2.Zero;
        stage.Follow(center, close ? detailSize : 0); stage.Advance(clock);
    }
    void ShowIsland()
    {
        if (rocky != null) { RemoveChild(rocky); rocky.QueueFree(); }
        var place = beachReference
            ? new Place("sample-rock", PlaceKind.Island, default, 355.70514f, 2273309013)
            : new Place("sample-rock", PlaceKind.Island, default, IslandSizes[islandSize], IslandStyles[islandStyle] + variant);
        detailSize = MathF.Max(6.2f, place.Radius * .02f);
        rocky = EnvironmentArt3D.Build(place);
        AddChild(rocky);
        bool giant = place.Radius > 360;
        // Keep the normal camera and boat scale; make room for the giant footprint.
        rocky.Position = giant ? new(1, 0, 0) : new(4, 0, .4f);
        boat.Position = giant ? new(-6.3f, 0, 4.6f) : Vector3.Zero;
        home.Visible = crab.Visible = !giant;
        status.Text = $"{EnvironmentArt3D.IslandScenery(place.Radius, place.Style)} · {place.Shape!.Profile} · radius {place.Radius:0.#} · seed {place.Style} · {(close ? "detail" : "gameplay scale")}\n"
            + "Space shape · R size · V seed · B reference · P prison · T tower · Tab scale · F5 refresh · F12 capture";
        GD.Print($"ISLAND SAMPLE scenery={EnvironmentArt3D.IslandScenery(place.Radius, place.Style)} profile={place.Shape!.Profile} radius={place.Radius} style={place.Style}");
    }
    public override async void _UnhandledKeyInput(InputEvent ev)
    {
        if (ev is not InputEventKey { Pressed: true, Echo: false } key) return;
        switch (key.Keycode)
        {
            case Key.P: beachReference = false; islandStyle = 8; islandSize = 3; variant = 0; close = false; break;
            case Key.T: beachReference = false; islandStyle = 9; islandSize = 1; variant = 0; close = false; break;
            case Key.B: beachReference = !beachReference; break;
            case Key.Tab: close = !close; break;
            case Key.Space:
                beachReference = false;
                islandStyle = (islandStyle + 1) % IslandStyles.Length; variant = 0; break;
            case Key.V:
                beachReference = false;
                var profile = new IslandShape(IslandSizes[islandSize], IslandStyles[islandStyle]).Profile;
                do { variant++; } while (new IslandShape(IslandSizes[islandSize], IslandStyles[islandStyle] + variant).Profile != profile);
                break;
            case Key.R: beachReference = false; islandSize = (islandSize + 1) % IslandSizes.Length; break;
            case Key.F5: SaveSettings(); GetTree().Quit(75); return;
            case Key.F12: break;
            default: return;
        }
        if (key.Keycode != Key.F12) { SaveSettings(); ShowIsland(); }
        if (key.Keycode == Key.F12)
        {
            await ToSignal(RenderingServer.Singleton, RenderingServer.SignalName.FramePostDraw);
            var folder = ProjectSettings.GlobalizePath("res://evidence");
            System.IO.Directory.CreateDirectory(folder);
            uint seed = beachReference ? 2273309013 : IslandStyles[islandStyle] + variant;
            float radius = beachReference ? 355.70514f : IslandSizes[islandSize];
            var profile = new IslandShape(radius, seed).Profile;
            var file = folder + "/" + DateTime.Now.ToString("yyyyMMdd-HHmmss-fff") + $"-art-{profile}-{radius}-{seed}-" + (close ? "detail" : "scale") + ".png";
            GetViewport().GetTexture().GetImage().SavePng(file);
            GD.Print($"ART SAMPLE {file} renderer={RenderingServer.GetCurrentRenderingMethod()} fps={Engine.GetFramesPerSecond()} draws={Performance.GetMonitor(Performance.Monitor.RenderTotalDrawCallsInFrame)}");
        }
    }
    void SaveSettings()
    {
        var settings = new ConfigFile();
        settings.SetValue("preview", "close", close);
        settings.SetValue("preview", "reference", beachReference);
        settings.SetValue("preview", "style", islandStyle);
        settings.SetValue("preview", "size", islandSize);
        settings.SetValue("preview", "variant", (long)variant);
        settings.Save(SettingsPath);
    }

}
