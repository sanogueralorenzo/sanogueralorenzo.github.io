using Godot;
using BoatsNBeasts.Core;
namespace BoatsNBeasts;

// Separate native art proof, never constructs or changes a gameplay Voyage.
public partial class ArtSample : Node3D
{
    NativeStage3D stage = null!;
    float clock;
    bool close;
    bool boatDetail;
    BoatKind boatKind = BoatKind.Mage;
    float detailSize = 6.2f;
    bool beachReference = true;
    bool seaWreck;
    bool whirlpool;
    const string SettingsPath = "user://art-preview.cfg";
    Label status = null!;
    Node3D rocky = null!;
    Node3D home = null!, boat = null!, crab = null!;
    int islandStyle;
    int islandSize = 1;
    uint variant;
    LandmarkSizes landmarkSizes = new();
    // Fixed production seeds cover the eight coastline families.
    static readonly uint[] IslandStyles = [4, 6, 1, 2, 12, 32, 33, 34, 29, 5, 14, 15, 17, 197, 514, 95, 282];
    static readonly float[] IslandSizes = [95, 200, 330, OceanWorld.MaxIslandRadius];
    public override void _Ready()
    {
        var settings = new ConfigFile();
        if (settings.Load(SettingsPath) == Error.Ok)
        {
            seaWreck = (bool)settings.GetValue("preview", "sea_wreck", false);
            whirlpool = (bool)settings.GetValue("preview", "whirlpool", false);
            close = (bool)settings.GetValue("preview", "close", false);
            beachReference = (bool)settings.GetValue("preview", "reference", true);
            islandStyle = Math.Clamp((int)settings.GetValue("preview", "style", 0), 0, IslandStyles.Length - 1);
            islandSize = Math.Clamp((int)settings.GetValue("preview", "size", 1), 0, IslandSizes.Length - 1);
            variant = (uint)(long)settings.GetValue("preview", "variant", 0L);
            landmarkSizes = new(
                (float)settings.GetValue("landmarks", "tavern", landmarkSizes.Tavern),
                (float)settings.GetValue("landmarks", "shipwreck", landmarkSizes.Shipwreck),
                (float)settings.GetValue("landmarks", "cave", landmarkSizes.SeaCave),
                (float)settings.GetValue("landmarks", "arch", landmarkSizes.AncientArch),
                (float)settings.GetValue("landmarks", "lighthouse", landmarkSizes.Lighthouse),
                (float)settings.GetValue("landmarks", "market", landmarkSizes.MarketStall),
                (float)settings.GetValue("landmarks", "windmill", landmarkSizes.Windmill));
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
        if (boatDetail)
        {
            var deck = boat.ToGlobal(new Vector3(0, 0, .18f));
            center = new Vector2(deck.X, deck.Z - .4f) * 100;
        }
        stage.Follow(center, boatDetail ? 1.7f : close ? detailSize : 0); stage.Advance(clock);
        ActorArt3D.AnimateBoat(boat, clock, 0, 0);
    }
    void ShowIsland()
    {
        if (rocky != null) { RemoveChild(rocky); rocky.QueueFree(); }
        var place = whirlpool ? new Place("sample-whirlpool", PlaceKind.Whirlpool, default, 260, 23) : seaWreck ? new Place("sample-wreck", PlaceKind.Shipwreck, default, landmarkSizes.ForKind(3) * OceanWorld.ShipwreckUnitRadius, 15) : beachReference
            ? new Place("sample-rock", PlaceKind.Island, default, 355.70514f, 2273309013)
            : new Place("sample-rock", PlaceKind.Island, default, IslandSizes[islandSize], IslandStyles[islandStyle] + variant);
        detailSize = MathF.Max(6.2f, place.Radius * .02f);
        rocky = EnvironmentArt3D.Build(place, landmarkSizes);
        AddChild(rocky);
        bool giant = place.Radius > 360;
        // Keep the normal camera and boat scale; make room for the giant footprint.
        rocky.Position = giant ? new(1, 0, 0) : new(4, 0, .4f);
        stage.SetWhirlpools(rocky is Whirlpool3D vortex ? new[] { vortex } : System.Array.Empty<Whirlpool3D>());
        boat.Position = giant ? new(-6.3f, 0, 4.6f) : Vector3.Zero;
        home.Visible = crab.Visible = !giant;
        string scenery = whirlpool ? "Whirlpool" : seaWreck ? "Shipwreck" : EnvironmentArt3D.IslandScenery(place.Radius, place.Style);
        float size = scenery switch { "Pirate tavern" => landmarkSizes.Tavern, "Shipwreck" => landmarkSizes.Shipwreck, "Sea cave" => landmarkSizes.SeaCave, "Ancient arch" => landmarkSizes.AncientArch, "Lighthouse" => landmarkSizes.Lighthouse, "Market stall" => landmarkSizes.MarketStall, "Windmill" => landmarkSizes.Windmill, _ => 0 };
        string sizeLabel = size > 0 ? $" · model size {size:0.00}" : "";
        status.Text = $"{scenery}{sizeLabel} · {place.Shape?.Profile.ToString() ?? "Open water"} · radius {place.Radius:0.#} · seed {place.Style} · {(close ? "detail" : "gameplay scale")}\n"
            + "Space shape · R island size · V seed · B reference · P prison · T tower · Tab view · F5 refresh · F12 capture\n1 lighthouse · 2 tavern · 3 market · 6 mill · 7 wreck · 8 cave · 9 arch · O land/sea wreck · +/- size · C crew · arrows turn · K boat · W whirlpool";
        GD.Print($"ISLAND SAMPLE scenery={scenery} profile={place.Shape?.Profile.ToString() ?? "Open water"} radius={place.Radius} style={place.Style}");
    }
    public override async void _UnhandledKeyInput(InputEvent ev)
    {
        if (ev is not InputEventKey { Pressed: true, Echo: false } key) return;
        if (key.Keycode == Key.C) { boatDetail = !boatDetail; return; }
        if (boatDetail && key.Keycode is Key.Left or Key.Right)
        {
            boat.RotateY(key.Keycode == Key.Left ? -.45f : .45f); return;
        }
        if (boatDetail && key.Keycode == Key.K)
        {
            boatKind = (BoatKind)(((int)boatKind + 1) % 3);
            var replacement = ActorArt3D.Boat(boatKind, [8, 8, 0, 0, 8, 8]);
            replacement.Transform = boat.Transform;
            RemoveChild(boat); boat.QueueFree(); boat = replacement; AddChild(boat); return;
        }
        boatDetail = false;
        bool previousWhirlpool = whirlpool;
        if (key.Keycode is not (Key.Tab or Key.F5 or Key.F12)) whirlpool = false;
        switch (key.Keycode)
        {
            case Key.W: whirlpool = true; seaWreck = false; beachReference = false; close = true; break;
            case Key.P: seaWreck = false; beachReference = false; islandStyle = 8; islandSize = 3; variant = 0; close = false; break;
            case Key.T: seaWreck = false; beachReference = false; islandStyle = 9; islandSize = 1; variant = 0; close = false; break;
            case Key.Key1: SelectLandmark(14); break;
            case Key.Key3: SelectLandmark(15); break;
            case Key.Key6: SelectLandmark(16); break;
            case Key.O: if (seaWreck || (!beachReference && EnvironmentArt3D.IslandScenery(IslandSizes[islandSize], IslandStyles[islandStyle] + variant) == "Shipwreck")) seaWreck = !seaWreck; break;
            case Key.Key2: SelectLandmark(10); break;
            case Key.Key7: SelectLandmark(11); break;
            case Key.Key8: SelectLandmark(12); break;
            case Key.Key9: SelectLandmark(13); break;
            case Key.Plus: case Key.Equal: case Key.KpAdd: ResizeLandmark(.20f); break;
            case Key.Minus: case Key.KpSubtract: ResizeLandmark(-.20f); break;
            case Key.B: seaWreck = false; beachReference = !beachReference; break;
            case Key.Tab: close = !close; break;
            case Key.Space:
                seaWreck = false; beachReference = false;
                islandStyle = (islandStyle + 1) % IslandStyles.Length; variant = 0; break;
            case Key.V:
                seaWreck = false; beachReference = false;
                var profile = new IslandShape(IslandSizes[islandSize], IslandStyles[islandStyle]).Profile;
                do { variant++; } while (new IslandShape(IslandSizes[islandSize], IslandStyles[islandStyle] + variant).Profile != profile);
                break;
            case Key.R: seaWreck = false; beachReference = false; islandSize = (islandSize + 1) % IslandSizes.Length; break;
            case Key.F5: SaveSettings(); GetTree().Quit(75); return;
            case Key.F12: break;
            default: whirlpool = previousWhirlpool; return;
        }
        if (key.Keycode != Key.F12) { SaveSettings(); ShowIsland(); }
        if (key.Keycode == Key.F12)
        {
            await ToSignal(RenderingServer.Singleton, RenderingServer.SignalName.FramePostDraw);
            var folder = ProjectSettings.GlobalizePath("res://evidence");
            System.IO.Directory.CreateDirectory(folder);
            uint seed = whirlpool ? 23 : seaWreck ? 15 : beachReference ? 2273309013 : IslandStyles[islandStyle] + variant;
            float radius = whirlpool ? 260 : seaWreck ? landmarkSizes.ForKind(3) * OceanWorld.ShipwreckUnitRadius : beachReference ? 355.70514f : IslandSizes[islandSize];
            var profile = seaWreck || whirlpool ? "OpenWater" : new IslandShape(radius, seed).Profile.ToString();
            var file = folder + "/" + DateTime.Now.ToString("yyyyMMdd-HHmmss-fff") + $"-art-{profile}-{radius}-{seed}-" + (close ? "detail" : "scale") + ".png";
            GetViewport().GetTexture().GetImage().SavePng(file);
            GD.Print($"ART SAMPLE {file} renderer={RenderingServer.GetCurrentRenderingMethod()} fps={Engine.GetFramesPerSecond()} draws={Performance.GetMonitor(Performance.Monitor.RenderTotalDrawCallsInFrame)}");
        }
    }
    void SelectLandmark(int style)
    {
        seaWreck = false; beachReference = false; islandStyle = style; islandSize = 2; variant = 0; close = false;
    }
    void ResizeLandmark(float step)
    {
        if (beachReference) return;
        string scenery = seaWreck ? "Shipwreck" : EnvironmentArt3D.IslandScenery(IslandSizes[islandSize], IslandStyles[islandStyle] + variant);
        float Adjust(float size) => Math.Clamp(size + step, .25f, 4f);
        landmarkSizes = scenery switch
        {
            "Pirate tavern" => landmarkSizes with { Tavern = Adjust(landmarkSizes.Tavern) },
            "Shipwreck" => landmarkSizes with { Shipwreck = Adjust(landmarkSizes.Shipwreck) },
            "Sea cave" => landmarkSizes with { SeaCave = Adjust(landmarkSizes.SeaCave) },
            "Ancient arch" => landmarkSizes with { AncientArch = Adjust(landmarkSizes.AncientArch) },
            "Lighthouse" => landmarkSizes with { Lighthouse = Adjust(landmarkSizes.Lighthouse) },
            "Market stall" => landmarkSizes with { MarketStall = Adjust(landmarkSizes.MarketStall) },
            "Windmill" => landmarkSizes with { Windmill = Adjust(landmarkSizes.Windmill) },
            _ => landmarkSizes
        };
    }
    void SaveSettings()
    {
        var settings = new ConfigFile();
        settings.SetValue("preview", "close", close);
        settings.SetValue("preview", "sea_wreck", seaWreck);
        settings.SetValue("preview", "whirlpool", whirlpool);
        settings.SetValue("preview", "reference", beachReference);
        settings.SetValue("preview", "style", islandStyle);
        settings.SetValue("preview", "size", islandSize);
        settings.SetValue("preview", "variant", (long)variant);
        settings.SetValue("landmarks", "tavern", landmarkSizes.Tavern);
        settings.SetValue("landmarks", "shipwreck", landmarkSizes.Shipwreck);
        settings.SetValue("landmarks", "cave", landmarkSizes.SeaCave);
        settings.SetValue("landmarks", "arch", landmarkSizes.AncientArch);
        settings.SetValue("landmarks", "lighthouse", landmarkSizes.Lighthouse);
        settings.SetValue("landmarks", "market", landmarkSizes.MarketStall);
        settings.SetValue("landmarks", "windmill", landmarkSizes.Windmill);
        settings.Save(SettingsPath);
    }

}
