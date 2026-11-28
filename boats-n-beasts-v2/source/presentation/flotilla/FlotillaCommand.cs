using BoatsNBeasts.Core;
using Godot;
using N = System.Numerics.Vector2;

namespace BoatsNBeasts;

public partial class FlotillaCommand : CrewRun
{
    public CampaignOrder Order { get; set; } = FreeFleet.CinderCharter();
    public float StartingCondition { get; set; } = 1;
    public float Condition => Battle?.Condition ?? StartingCondition;
    public FleetCommand Battle { get; private set; } = null!;
    public override int SilverEarned => Battle?.Silver ?? 0;
    public override bool AskShipmate(Shipmate mate) => Battle.CallShipmate(mate);
    internal OceanView3D Sea = null!;
    internal FlotillaCommandPilot? PilotView;
    Camera3D lens = null!;
    internal bool Chart;
    internal bool MenuUp => panel != null;
    CanvasLayer canvas = null!;
    FlotillaCommandHud hud = null!;
    AudioStreamPlayer voice = null!;
    Control? panel;
    readonly List<Action> picks = [];
    readonly List<Node3D> boats = [];
    readonly Dictionary<FleetPost, Node3D> posts = [];
    Node3D flagship = null!, hospital = null!, falseFlag = null!, fog = null!;
    readonly Dictionary<(string Kind, string Name), Node3D> fittings = [];
    FleetField? displayed;
    int heardSilver;
    bool returning;
    public override void _Ready()
    {
        Battle = new(Order, Seed, Stores, Outfit, Vessel, StartingCondition);
        Sea = new() { Name = "FleetRoads", Voyage = Battle.Ship, Figurehead = Figurehead, CustomPlace = p => BluewaterCoast.Build(p, Battle.Country, false) };
        AddChild(Sea); Sea.PaintWater(BluewaterCoast.Water(Battle.Country.Climate)); Sea.OpenChart(); lens = GetViewport().GetCamera3D();
        foreach (var ally in Battle.Allies)
        { var vessel = FlotillaCommandArt.Hull(ally.Role, Battle.Country); Sea.AddChild(vessel); boats.Add(vessel); }
        flagship = FlotillaCommandArt.Antagonist(Battle); Sea.AddChild(flagship);
        hospital = FlotillaCommandArt.Hospital(Battle.Country); Sea.AddChild(hospital);
        falseFlag = FlotillaCommandArt.Hull(FleetRole.Sloop, Battle.Country); falseFlag.Scale = Vector3.One * 1.30f; Sea.AddChild(falseFlag);
        fog = FlotillaCommandArt.Haze(Battle.Country); Sea.AddChild(fog);
        voice = new() { VolumeDb = -16, MaxPolyphony = 3 }; AddChild(voice);
        canvas = new(); AddChild(canvas); hud = new() { Game = this, MouseFilter = Control.MouseFilterEnum.Ignore }; canvas.AddChild(hud); hud.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        Refresh();
    }
    static bool Down(Key a, Key b) => Input.IsPhysicalKeyPressed(a) || Input.IsPhysicalKeyPressed(b);
    static N Helm() => new((Down(Key.D, Key.Right) ? 1 : 0) - (Down(Key.A, Key.Left) ? 1 : 0), (Down(Key.S, Key.Down) ? 1 : 0) - (Down(Key.W, Key.Up) ? 1 : 0));
    public override void _PhysicsProcess(double delta)
    {
        if (returning) return;
        if (Battle.AtSea)
        {
            bool mouse = Input.IsMouseButtonPressed(MouseButton.Left);
            N? aim = Battle.Pilot != null ? null : mouse ? Sea.WorldPoint(GetViewport().GetMousePosition()) : Battle.Aim();
            Battle.Tick((float)delta, new(Helm(), Input.IsPhysicalKeyPressed(Key.Shift), mouse || Input.IsPhysicalKeyPressed(Key.Space), aim));
            if (Sea.IsInsideTree()) { foreach (var ev in Battle.Ship.Events) Sea.Effect(ev); Sea.Advance((float)delta); }
            Battle.Ship.Events.Clear();
            if (Battle.Silver > heardSilver) { heardSilver = Battle.Silver; Tone(68, true); }
        }
        Refresh();
    }
    public override void _Input(InputEvent input)
    {
        if (MenuUp && input is InputEventKey k && (k.Keycode == Key.Space || k.PhysicalKeycode == Key.Space)) GetViewport().SetInputAsHandled();
    }
    public override void _UnhandledInput(InputEvent input)
    {
        if (returning || MenuUp || !Battle.AtSea || Battle.Pilot != null || input is not InputEventMouseButton { Pressed: true, ButtonIndex: MouseButton.Right } click) return;
        var point = Sea.WorldPoint(click.Position);
        int target = Enumerable.Range(0, Battle.Stations.Count).Where(i => !Battle.Stations[i].Done).MinBy(i => N.DistanceSquared(Battle.Stations[i].Position, point));
        Battle.SelectPost(target); Battle.Dispatch(); Tone(63, false); GetViewport().SetInputAsHandled(); Refresh();
    }
    public override void _UnhandledKeyInput(InputEvent input)
    {
        if (returning || input is not InputEventKey { Pressed: true, Echo: false } k) return;
        var key = k.PhysicalKeycode == Key.None ? k.Keycode : k.PhysicalKeycode;
        var screen = GetViewport();
        int num = key switch { Key.Key1 or Key.Kp1 => 0, Key.Key2 or Key.Kp2 => 1, Key.Key3 or Key.Kp3 => 2, _ => -1 };
        if (MenuUp)
        {
            int pick = num >= 0 ? num : key is Key.Enter or Key.KpEnter ? 0 : -1;
            if (pick < 0 || pick >= picks.Count) return; picks[pick]();
        }
        else if (num >= 0) { Battle.Select(num); Tone(58 + num * 3, false); }
        else if (key == Key.Tab) { Battle.Cycle(); Tone(57, false); }
        else if (key == Key.Q || key is Key.Enter or Key.KpEnter && Battle.Field == FleetField.Refuge) { Battle.Dispatch(); Tone(65, true); }
        else if (key == Key.G) { if (Battle.Hands()) Tone(69, true); }
        else if (key == Key.R) { Battle.Recall(); Tone(56, false); }
        else if (key == Key.E) Battle.Patch();
        else if (key == Key.M) Chart = !Chart;
        else return;
        screen.SetInputAsHandled(); if (!returning) Refresh();
    }
    void Tone(int note, bool bell) { voice.Stream = QuayTone.Note(note, bell); voice.Play(); }
    static void Pose(Node3D model, N p, N bow, float y)
    {
        model.Position = NativeStage3D.Point(p, y);
        model.Rotation = new(0, -MathF.Atan2(bow.X, -bow.Y), 0);
    }
    public override void _ExitTree()
    {
        if (Sea != null && !Sea.IsInsideTree() && Sea.GetParent() == null) Sea.QueueFree();
    }
    void Refresh()
    {
        if (Battle.Pilot != null)
        {
            if (PilotView == null)
            {
                RemoveChild(Sea); PilotView = new() { Fleet = Battle, Run = Battle.Pilot }; AddChild(PilotView); Chart = false; Tone(67, true);
            }
            PilotView.DrawFleet(); hud.QueueRedraw(); return;
        }
        if (PilotView != null)
        {
            RemoveChild(PilotView); PilotView.QueueFree(); PilotView = null; AddChild(Sea); lens.MakeCurrent(); Sea.OpenChart(); Sea.Advance(.001f);
        }
        for (int i = 0; i < boats.Count; i++)
        {
            var ally = Battle.Allies[i]; Pose(boats[i], ally.Position, ally.Bow, ally.Afloat ? .02f * MathF.Sin(Battle.Clock * 1.8f + i) : -.16f);
            if (!ally.Afloat) boats[i].RotateZ(.17f);
        }
        foreach (var stale in posts.Keys.Where(p => !Battle.Stations.Contains(p) || p.Done).ToArray()) { posts[stale].QueueFree(); posts.Remove(stale); }
        foreach (var post in Battle.Stations.Where(p => !p.Done && p.Task is not (FleetTask.Rally or FleetTask.Board)))
        {
            if (!posts.TryGetValue(post, out var prop))
            {
                var kind = post.Task switch { FleetTask.Rescue => "wreck", FleetTask.Ferry => "convoy", FleetTask.Signal => "gate", FleetTask.Cut => "picket", _ => "gate" };
                prop = BluewaterArt.Prop(Battle.Country, kind); Sea.AddChild(prop); posts[post] = prop;
            }
            prop.Position = NativeStage3D.Point(post.Position);
        }
        flagship.Visible = Battle.EnemyVisible; if (flagship.Visible) Pose(flagship, Battle.EnemyHull, Battle.EnemyBow, .04f * MathF.Sin(Battle.Clock * 1.5f));
        falseFlag.Visible = Battle.Clouds && !Battle.FalseLight;
        if (falseFlag.Visible) Pose(falseFlag, Battle.Decoy, Battle.EnemyBow, 0);
        fog.Visible = Battle.Clouds; if (fog.Visible) fog.Position = NativeStage3D.Point(Battle.Fog);
        var marks = Battle.AtSea ? Battle.Workmarks().Where(m => m.Name != "Hospital tender").ToArray() : [];
        foreach (var old in fittings.Keys.Where(k => !marks.Any(m => (m.Kind, m.Name) == k)).ToArray()) { fittings[old].QueueFree(); fittings.Remove(old); }
        foreach (var mark in marks)
        {
            var key = (mark.Kind, mark.Name);
            if (!fittings.TryGetValue(key, out var prop)) { prop = BluewaterArt.Prop(Battle.Country, mark.Kind); prop.Scale = Vector3.One * .70f; Sea.AddChild(prop); fittings[key] = prop; }
            prop.Position = NativeStage3D.Point(mark.Position);
        }
        hospital.Visible = Battle.Field is FleetField.Rescue or FleetField.Refuge; hospital.Position = NativeStage3D.Point(Battle.Refuge);
        if (displayed != Battle.Field) { displayed = Battle.Field; if (panel != null) { canvas.RemoveChild(panel); panel.QueueFree(); panel = null; picks.Clear(); } if (!Battle.AtSea) ShowBoard(); else Chart = false; }
        hud.QueueRedraw();
    }
    void ShowBoard()
    {
        panel = new ColorRect { Color = new("102039a9"), MouseFilter = Control.MouseFilterEnum.Stop };
        canvas.AddChild(panel); panel.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        var centered = new CenterContainer(); panel.AddChild(centered); centered.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        var sheet = new PanelContainer { CustomMinimumSize = new(700, 0) };
        sheet.AddThemeStyleboxOverride("panel", HarborType.Box(new("183540"), new(Battle.Country.Accent), 23, 17)); centered.AddChild(sheet);
        var box = new VBoxContainer(); box.AddThemeConstantOverride("separation", 9); sheet.AddChild(box);
        void Line(string s, int n, bool title = false) => box.AddChild(HarborType.Text(s, n, title ? HarborType.Cream : HarborType.Brass, title));
        void Choice(string label, Action action)
        {
            int slot = picks.Count;
            void Pick() { if (returning) return; action(); if (!returning) Refresh(); }
            picks.Add(Pick); var button = HarborType.Button($"{slot + 1}    {label}", Pick, slot == 0); box.AddChild(button); if (slot == 0) button.GrabFocus();
        }
        Line(Order.Region.ToUpperInvariant() + "    /    FLOTILLA COMMAND", 14);
        if (Battle.Field == FleetField.Muster)
        {
            Line(Order.Title, 30, true); Line(Order.Brief, 18); Line(Order.Objective, 18);
            foreach (var a in Battle.Allies) Line($"{(int)a.Role + 1}    {a.Skipper} aboard {a.Name}    ·    {a.Role switch { FleetRole.Tender => "Fast rescue tender, two rescue berths", FleetRole.Tug => "Shield tug, fast under tow", _ => "Signal sloop, long-range deck gun" }}", 17);
            Line("Select a hull with 1–3, choose a post with Tab, then Q to send it. Sail the cutter to the green bearing and press G to work alongside a crew.", 16);
            Choice("Raise the company pennant", Battle.Launch); return;
        }
        if (Battle.Field == FleetField.Refit)
        {
            Line("At the sheltered berth", 27, true); Line($"{Battle.HullsAfloat} hulls answering   ·   {Battle.Rescued} rescued   ·   {SilverAboard} silver", 18);
            Choice("Send the carpenters   ·   Repair all sailing hulls and stow one kit", () => Battle.Refit(0));
            Choice("Lend the tug extra shield boards   ·   Wider protection", () => Battle.Refit(1));
            Choice("Fit longer gun purchases   ·   Faster cutter gun, heavier allied fire", () => Battle.Refit(2)); return;
        }
        Line(Battle.Won ? "The company answers at the refuge" : "The flotilla returns by launch", 29, true);
        Line(Battle.Call, 18); Line($"{SilverAboard} silver    ·    {Battle.HullsAfloat} hulls afloat", 18);
        Choice("Return to " + LandingName, () => { returning = true; if (Returned != null) Returned(Battle.Won, SilverEarned); else GetTree().ChangeSceneToFile("res://main.tscn"); });
    }
}
