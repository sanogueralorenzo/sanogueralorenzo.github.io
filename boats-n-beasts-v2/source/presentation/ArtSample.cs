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
    BoatKind boatKind = BoatKind.Cutter;
    float detailSize = 6.2f;
    bool beachReference;
    bool whirlpool;
    const string SettingsPath = "user://art-preview.cfg";
    Label status = null!;
    Node3D rocky = null!;
    Node3D home = null!, boat = null!, crab = null!, shoal = null!;
    Node3D? wake;
    const int LighthouseStyle = 14, LighthouseSize = 3;
    int islandStyle = LighthouseStyle;
    int islandSize = LighthouseSize;
    uint variant;
    LandmarkSizes landmarkSizes = new();
    // Fixed production seeds cover the eight coastline families.
    static readonly uint[] IslandStyles = [4, 6, 1, 2, 12, 32, 33, 34, 29, 5, 14, 15, 17, 197, 620, 95, 282];
    static readonly float[] IslandSizes = [95, 200, 330, 565, OceanWorld.MaxIslandRadius];
    public override void _Ready()
    {
        var settings = new ConfigFile();
        if (settings.Load(SettingsPath) == Error.Ok)
        {
            whirlpool = (bool)settings.GetValue("preview", "whirlpool", false);
            close = (bool)settings.GetValue("preview", "close", false);
            beachReference = (bool)settings.GetValue("preview", "reference", false);
            islandStyle = Math.Clamp((int)settings.GetValue("preview", "style", LighthouseStyle), 0, IslandStyles.Length - 1);
            islandSize = Math.Clamp((int)settings.GetValue("preview", "size", LighthouseSize), 0, IslandSizes.Length - 1);
            variant = (uint)(long)settings.GetValue("preview", "variant", 0L);
            landmarkSizes = new(
                (float)settings.GetValue("landmarks", "tavern", landmarkSizes.Tavern),
                (float)settings.GetValue("landmarks", "cave", landmarkSizes.SeaCave),
                (float)settings.GetValue("landmarks", "arch", landmarkSizes.AncientArch),
                (float)settings.GetValue("landmarks", "lighthouse", landmarkSizes.Lighthouse),
                (float)settings.GetValue("landmarks", "market", landmarkSizes.MarketStall),
                (float)settings.GetValue("landmarks", "windmill", landmarkSizes.Windmill));
        }
        stage = new(); AddChild(stage);
        home = EnvironmentArt3D.Build(new Place("sample", PlaceKind.Harbor, default, 140, 147));
        AddChild(home); home.Position = new(-3.2f, 0, -1.4f);
        shoal = EnvironmentArt3D.Build(new Place("sample-shoal", PlaceKind.Island, default, 225, 64));
        AddChild(shoal); shoal.Position = new(8.27f, 0, 4.60f);
        boat = ActorArt3D.Boat(boatKind, [1, 0, 0, 0, 0, 0]);
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
        GetWindow().Title = "Boats ’n’ Beasts V2 · Art preview";
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
        ActorArt3D.Animate(crab, clock, 1);
        if (wake != null) wake.Visible = !boatDetail;
    }
    void ShowIsland()
    {
        if (rocky != null) { RemoveChild(rocky); rocky.QueueFree(); }
        var place = whirlpool ? new Place("sample-whirlpool", PlaceKind.Whirlpool, default, 260, 23) : beachReference
            ? new Place("sample-rock", PlaceKind.Island, default, 355.70514f, 2273309013)
            : new Place("sample-rock", PlaceKind.Island, default, IslandSizes[islandSize], IslandStyles[islandStyle] + variant);
        detailSize = MathF.Max(6.2f, place.Radius * .02f);
        rocky = EnvironmentArt3D.Build(place, landmarkSizes);
        AddChild(rocky);
        string scenery = whirlpool ? "Whirlpool" : EnvironmentArt3D.IslandScenery(place.Radius, place.Style);
        bool lighthouse = scenery == "Lighthouse";
        bool giant = place.Radius > 360;
        // Keep the normal camera and boat scale; make room for the giant footprint.
        rocky.Position = lighthouse ? new(-4.94f, 0, -.87f) : giant ? new(1, 0, 0) : new(4, 0, .4f);
        stage.SetWhirlpools(rocky is Whirlpool3D vortex ? new[] { vortex } : System.Array.Empty<Whirlpool3D>());
        boat.Position = lighthouse ? new(.49f, 0, 3.94f) : giant ? new(-6.3f, 0, 4.6f) : Vector3.Zero;
        boat.Rotation = new(0, lighthouse ? -.73f : -.7f, 0);
        crab.Position = lighthouse ? new(6.10f, 0, 4.75f) : new(-2, 0, 1.6f);
        crab.Rotation = new(0, lighthouse ? 3.05f : 2.2f, 0);
        home.Visible = !giant && !lighthouse;
        shoal.Visible = lighthouse && !close;
        crab.Visible = shoal.Visible || (!giant && !lighthouse);
        UpdateWake();
        float size = scenery switch { "Pirate tavern" => landmarkSizes.Tavern, "Sea cave" => landmarkSizes.SeaCave, "Ancient arch" => landmarkSizes.AncientArch, "Lighthouse" => landmarkSizes.Lighthouse, "Market stall" => landmarkSizes.MarketStall, "Windmill" => landmarkSizes.Windmill, _ => 0 };
        string sizeLabel = size > 0 ? $" · model size {size:0.00}" : "";
        status.Text = $"{scenery}{sizeLabel} · {place.Shape?.Profile.ToString() ?? "Open water"} · radius {place.Radius:0.#} · seed {place.Style} · {(close ? "detail" : "gameplay scale")}\n"
            + "Q islands · W prison · E tower · R lighthouse · T tavern · Y market · U mill · O cave · P arch\nA reference · S whirlpool · F island size · G seed · H smaller · J larger · K crew · L boat\nZ turn left · X turn right · C view · V refresh";
        GD.Print($"ISLAND SAMPLE scenery={scenery} profile={place.Shape?.Profile.ToString() ?? "Open water"} radius={place.Radius} style={place.Style}");
    }
    void UpdateWake()
    {
        if (wake != null) { RemoveChild(wake); wake.QueueFree(); wake = null; }
        if (!shoal.Visible) return;
        wake = Effects3D.PreviewWake(boat.Position, -boat.Basis.Z);
        AddChild(wake);
    }
    public override void _UnhandledKeyInput(InputEvent ev)
    {
        if (ev is not InputEventKey { Pressed: true, Echo: false } key) return;
        if (key.Keycode == Key.K) { boatDetail = !boatDetail; return; }
        if (key.Keycode is Key.Z or Key.X)
        {
            boat.RotateY(key.Keycode == Key.Z ? -.45f : .45f);
            UpdateWake();
            return;
        }
        if (boatDetail && key.Keycode == Key.L)
        {
            boatKind = (BoatKind)(((int)boatKind + 1) % 3);
            var replacement = ActorArt3D.Boat(boatKind, [8, 8, 0, 0, 8, 8]);
            replacement.Transform = boat.Transform;
            RemoveChild(boat); boat.QueueFree(); boat = replacement; AddChild(boat); return;
        }
        boatDetail = false;
        bool previousWhirlpool = whirlpool;
        if (key.Keycode is not (Key.C or Key.V)) whirlpool = false;
        switch (key.Keycode)
        {
            case Key.S: whirlpool = true; beachReference = false; close = true; break;
            case Key.W: beachReference = false; islandStyle = 8; islandSize = IslandSizes.Length - 1; variant = 0; close = false; break;
            case Key.E: beachReference = false; islandStyle = 9; islandSize = 1; variant = 0; close = false; break;
            case Key.R: SelectLandmark(LighthouseStyle, LighthouseSize); break;
            case Key.Y: SelectLandmark(15); break;
            case Key.U: SelectLandmark(16); break;
            case Key.T: SelectLandmark(10); break;
            case Key.O: SelectLandmark(12); break;
            case Key.P: SelectLandmark(13); break;
            case Key.J: ResizeLandmark(.20f); break;
            case Key.H: ResizeLandmark(-.20f); break;
            case Key.A: beachReference = !beachReference; break;
            case Key.C: close = !close; break;
            case Key.Q:
                beachReference = false;
                islandStyle = (islandStyle + 1) % IslandStyles.Length; variant = 0; break;
            case Key.G:
                beachReference = false;
                var profile = new IslandShape(IslandSizes[islandSize], IslandStyles[islandStyle]).Profile;
                do { variant++; } while (new IslandShape(IslandSizes[islandSize], IslandStyles[islandStyle] + variant).Profile != profile);
                break;
            case Key.F: beachReference = false; islandSize = (islandSize + 1) % IslandSizes.Length; break;
            case Key.V: SaveSettings(); GetTree().Quit(75); return;
            default: whirlpool = previousWhirlpool; return;
        }
        SaveSettings(); ShowIsland();
    }
    void SelectLandmark(int style, int size = 2)
    {
        beachReference = false; islandStyle = style; islandSize = size; variant = 0; close = false;
    }
    void ResizeLandmark(float step)
    {
        if (beachReference) return;
        string scenery = EnvironmentArt3D.IslandScenery(IslandSizes[islandSize], IslandStyles[islandStyle] + variant);
        float Adjust(float size) => Math.Clamp(size + step, .25f, 4f);
        landmarkSizes = scenery switch
        {
            "Pirate tavern" => landmarkSizes with { Tavern = Adjust(landmarkSizes.Tavern) },
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
        settings.SetValue("preview", "whirlpool", whirlpool);
        settings.SetValue("preview", "reference", beachReference);
        settings.SetValue("preview", "style", islandStyle);
        settings.SetValue("preview", "size", islandSize);
        settings.SetValue("preview", "variant", (long)variant);
        settings.SetValue("landmarks", "tavern", landmarkSizes.Tavern);
        settings.SetValue("landmarks", "cave", landmarkSizes.SeaCave);
        settings.SetValue("landmarks", "arch", landmarkSizes.AncientArch);
        settings.SetValue("landmarks", "lighthouse", landmarkSizes.Lighthouse);
        settings.SetValue("landmarks", "market", landmarkSizes.MarketStall);
        settings.SetValue("landmarks", "windmill", landmarkSizes.Windmill);
        settings.Save(SettingsPath);
    }

}
