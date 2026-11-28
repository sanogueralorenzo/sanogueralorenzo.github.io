using BoatsNBeasts.Core;
using Godot;
using N = System.Numerics.Vector2;

namespace BoatsNBeasts;

public partial class PrizeWatch : CrewRun
{
    public CampaignOrder Order { get; set; } = FarLedger.Arcs.SelectMany(a => a.Islands).SelectMany(i => i.Outings).First(o => o.PrizeWatch);
    public PrizeTheater Watch { get; private set; } = null!;
    public PrizeBoarding? Board { get; private set; }
    public CrewRun? Child { get; private set; }
    public override CrewRun? ActiveWatch=>Child;
    public override int SilverEarned => (Watch?.Purse ?? 0) + (Child?.SilverEarned ?? Board?.Silver ?? 0);
    public override bool AskShipmate(Shipmate mate) => Child?.AskShipmate(mate) ?? Board?.CallShipmate(mate) ?? (!MenuUp && Watch.Ship.CallShipmate(mate));
    internal OceanView3D Sea = null!;
    internal PrizeDeckView? Deck;
    internal bool MenuUp => sheet != null;
    CanvasLayer canvas = null!;
    PrizeHud hud = null!;
    Control? sheet;
    readonly List<Action> choices = [];
    readonly List<Node3D> hulls = [];
    Node3D? packet, stores, flag, prize, rival;
    readonly List<(string Kind, Node3D Model)> inquestProps = [];
    Camera3D seaLens = null!;
    AudioStreamPlayer signal = null!;
    int heardRoom, heardWork;
    bool heardBrake;
    bool hook, roll, use, heal, exiting, settling, stageChoice;
    bool upperRoute;
    int shownReach = -1;
    float clock;
    string menuKey = "";
    public override void _Ready()
    {
        Watch = new(Order, Seed, Stores, Outfit, Vessel); signal = new() { VolumeDb = -15, MaxPolyphony = 3 }; AddChild(signal);
        Sea = new() { Name = "PrizeRoads", Voyage = Watch.Ship, Figurehead = Figurehead, CustomPlace = p => BluewaterCoast.Build(p, Watch.Country, false) };
        AddChild(Sea); Sea.PaintWater(BluewaterCoast.Water(Watch.Country.Climate)); Sea.OpenChart(); seaLens = GetViewport().GetCamera3D();
        rival = BluewaterArt.Prop(Watch.Country, "picket"); Sea.AddChild(rival);
        packet = BluewaterArt.Prop(Watch.Country, "refuge"); Sea.AddChild(packet);
        stores = BluewaterArt.Prop(Watch.Country, "wreck"); Sea.AddChild(stores);
        flag = BluewaterArt.Prop(Watch.Country, "gate"); Sea.AddChild(flag);
        prize = BluewaterArt.Prop(Watch.Country, "convoy"); Sea.AddChild(prize);
        canvas = new(); AddChild(canvas); hud = new() { Game = this, MouseFilter = Control.MouseFilterEnum.Ignore }; canvas.AddChild(hud); hud.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        Render();
    }
    static bool Down(Key a, Key b) => Input.IsPhysicalKeyPressed(a) || Input.IsPhysicalKeyPressed(b);
    static N Helm() => new((Down(Key.D, Key.Right) ? 1 : 0) - (Down(Key.A, Key.Left) ? 1 : 0), (Down(Key.S, Key.Down) ? 1 : 0) - (Down(Key.W, Key.Up) ? 1 : 0));
    public override void _PhysicsProcess(double delta)
    {
        if (exiting || Child != null || settling) return;
        float dt = (float)delta;
        if (!MenuUp)
        {
            clock += dt;
            if (Board != null)
            {
                Board.Tick(dt, Helm(), Down(Key.Space, Key.J) || Input.IsMouseButtonPressed(MouseButton.Left), roll, hook, use, heal);
                if (Board.Room != heardRoom || Board.Fixed && heardWork != Board.Room)
                { Tone(Board.Fixed ? 67 : 55, true); heardRoom = Board.Room; if (Board.Fixed) heardWork = Board.Room; }
                else if (Board.MateAtBrake && !heardBrake) Tone(62, false);
                heardBrake = Board.MateAtBrake; Deck!.Sync(clock);
                if (Board.Won || Board.Lost) FinishDeck();
            }
            else if (Watch.Phase == PrizePhase.Board) OpenDeck();
            else if (!Watch.AtChild)
            {
                var fire = Input.IsPhysicalKeyPressed(Key.Space) || Input.IsMouseButtonPressed(MouseButton.Left);
                N? aim = Input.IsMouseButtonPressed(MouseButton.Left) ? Sea.WorldPoint(GetViewport().GetMousePosition()) : Watch.Aim();
                if (heal) Watch.Patch();
                var before = Watch.Phase; int silver = Watch.Purse;
                Watch.Tick(dt, new(Helm(), Input.IsPhysicalKeyPressed(Key.Shift), fire, aim), hook);
                if (Watch.Phase != before || Watch.Purse > silver) Tone(Watch.Phase == PrizePhase.Hail ? 60 : 67, true);
                foreach (var e in Watch.Ship.Events) Sea.Effect(e);
                Watch.Ship.Events.Clear(); Sea.Advance(dt);
                if (Watch.AtChild) { if (Watch.Phase == PrizePhase.Board) OpenDeck(); else stageChoice = true; }
            }
        }
        roll = hook = use = heal = false; Render();
    }
    public override void _Input(InputEvent input)
    {
        if (Child == null && MenuUp && input is InputEventKey k && (k.PhysicalKeycode == Key.Space || k.Keycode == Key.Space))
            GetViewport().SetInputAsHandled();
    }
    public override void _UnhandledKeyInput(InputEvent input)
    {
        if (exiting || Child != null || settling || input is not InputEventKey { Pressed: true, Echo: false } k) return;
        var key = k.PhysicalKeycode == Key.None ? k.Keycode : k.PhysicalKeycode;
        var view = GetViewport();
        if (MenuUp)
        {
            if (key == Key.M && manualChart) { manualChart = false; Render(); view.SetInputAsHandled(); return; }
            int pick = key switch { Key.Key1 or Key.Kp1 => 0, Key.Key2 or Key.Kp2 => 1, Key.Key3 or Key.Kp3 => 2, Key.Key4 or Key.Kp4 => 3, Key.Key5 or Key.Kp5 => 4, Key.Key6 or Key.Kp6 => 5, _ => -1 };
            if (pick < 0 || pick >= choices.Count) return; choices[pick]();
        }
        else if (key == Key.Q || Board != null && key == Key.K) hook = true;
        else if (key == Key.R || Board == null && key == Key.E) heal = true;
        else if (Board != null && key == Key.E) use = true;
        else if (Board != null && key == Key.Shift) roll = true;
        else if (Board == null && key == Key.X) Watch.DeployAlly();
        else if (Board == null && key == Key.Tab) Watch.Cycle();
        else if (key == Key.M && Board == null) { manualChart = !manualChart; Render(); }
        else return;
        view.SetInputAsHandled();
    }
    void Tone(int note, bool bell) { signal.Stream = QuayTone.Note(note, bell); signal.Play(); }
    bool manualChart;
    void OpenDeck()
    {
        heardRoom = heardWork = 0; heardBrake = false; Board = new(Watch, Seed + 13 * Watch.Index);
        RemoveChild(Sea); Deck = new() { Board = Board }; AddChild(Deck);
        Deck.Sync(clock); menuKey = "";
    }
    void RestoreOcean()
    {
        if (!Sea.IsInsideTree()) { AddChild(Sea); seaLens.MakeCurrent(); Sea.OpenChart(); Sea.Advance(.001f); }
    }
    void FinishDeck()
    {
        var b = Board!; Watch.FinishStage(b.Won, b.Silver, (float)b.Health / b.MaxHealth, b.Freed);
        RemoveChild(Deck!); Deck!.QueueFree(); Deck = null; Board = null; RestoreOcean(); menuKey = "";
    }
    void StartStage(bool hard)
    {
        if (Child != null) return;
        upperRoute = hard; stageChoice = false; CloseSheet();
        if (Sea.IsInsideTree()) RemoveChild(Sea);
        canvas.Hide(); Child = Watch.CommissionLeg switch
        {
            1 => new BluewaterVoyage { Order = Watch.CommissionPassage(hard) },
            2 => new KilnExpedition { Order = Watch.CommissionPort(hard) },
            _ => Watch.Phase == PrizePhase.Landfall ? MakeFort(hard) : MakeCrossing(hard)
        };
        Child.CarriedSilver=CarriedSilver+Watch.Purse; Child.Seed = Seed + 197 * Watch.Index; Child.Outfit = Outfit; Child.Stores = Stores; Child.Vessel = Vessel; Child.Figurehead = Figurehead; Child.LandingName = "the watch roads"; Child.Returned = FinishChild; AddChild(Child);
        if (Child is KilnExpedition foot) foot.Yard.ArriveByPost(Math.Max(.45f, 1 - Watch.Strain / 95f));
        if (Child is BluewaterVoyage sea)
        {
            var ship = sea.Course.Ship; TransferFittings(Watch.Ship, ship); ship.Health = Math.Max(1, ship.MaxHealth * Watch.HealthFraction);
        }
    }
    KilnExpedition MakeFort(bool hard)
    {
        LandingStep[] tasks = hard ?
            [new(LandingAction.Brace,YardSite.West,"The watch drum","Brace the warning drum before the keepers ring it"),
             new(LandingAction.Cut,YardSite.Crane,"Signal halyard","Cut the false flag from the high signal arm"),
             new(LandingAction.Haul,YardSite.East,"Counterweight chest","Haul the original lead seal to the dispatch steps")] :
            [new(LandingAction.Turn,YardSite.East,"Pilot’s lock","Turn the gate for the civilian signal crew"),
             new(LandingAction.Seat,YardSite.Crane,"Witness stamp","Seat the stamp on the public signal sheet"),
             new(LandingAction.Guide,YardSite.Ferry,"The tower witness","Bring the old signaler to the watch cutter")];
        return new()
        {
            Order = Order with
            {
                Id = Order.Id + "-signal",
                Title = hard ? "Cut down the false flag" : "The pilot’s witness",
                Duty = SeaDuty.Landing,
                Legs = string.IsNullOrEmpty(Order.Island) ? 7 : 5,
                Boss = hard ? "The Signal Bailiff" : "The Shutter Keeper",
                LandingSteps = tasks,
                Postal = false,
                PrizeWatch = false,
                Migration = false,
                Pilotage = false
            }
        };
    }
    BluewaterVoyage MakeCrossing(bool hard) => new()
    {
        Order = Order with
        {
            Id = Order.Id + "-roads",
            Title = hard ? "Run the customs line" : "The witnesses’ relief fleet",
            Duty = hard ? SeaDuty.Blockade : SeaDuty.Convoy,
            Legs = string.IsNullOrEmpty(Order.Island) ? 7 : 5,
            SeaStations = hard ? [SeaJob.Track, SeaJob.Cut, SeaJob.DriveOff, SeaJob.Relay] : [SeaJob.Tow, SeaJob.Sound, SeaJob.Guide, SeaJob.Relieve],
            Objective = hard ? "Open the examination booms and bring the pilots’ warrants back." : "Shepherd the witness lighters through the pilot gates.",
            Boss = hard ? "The Removal Tug" : "The Closed Gate",
            Homecoming = "The relief crews transfer their witnesses and provisions to the watch cutter.",
            Postal = false,
            PrizeWatch = false,
            Migration = false,
            Pilotage = false
        }
    };
    static void TransferFittings(Voyage from, Voyage to)
    {
        to.HullRank = from.HullRank; to.EngineRank = from.EngineRank; to.ReloadRank = from.ReloadRank; to.AreaRank = from.AreaRank;
        to.Level = from.Level; to.Xp = from.Xp;
        for (int i = 0; i < to.Weapons.Length; i++) to.Weapons[i] = Math.Max(to.Weapons[i], from.Weapons[i]);
    }
    void FinishChild(bool won, int silver)
    {
        if (Child == null || settling) return; settling = true;
        float remaining = Child switch { BluewaterVoyage s => s.Course.Ship.Health / s.Course.Ship.MaxHealth, KilnExpedition f => (float)f.Yard.Health / f.Yard.MaximumHealth, _ => 1 };
        if (Child is BluewaterVoyage sea && won)
        {
            TransferFittings(sea.Course.Ship, Watch.Ship);
        }
        Watch.FinishStage(won, silver, remaining, !upperRoute); var finished = Child; Child = null; RemoveChild(finished); finished.QueueFree();
        Callable.From(() => { if (exiting || !IsInsideTree()) return; RestoreOcean(); canvas.Show(); settling = false; stageChoice = Watch.AtChild; menuKey = ""; Render(); }).CallDeferred();
    }
    public override void _ExitTree()
    {
        if (Sea != null && !Sea.IsInsideTree() && Sea.GetParent() == null) Sea.QueueFree();
    }
    void Render()
    {
        if (Child != null || exiting || settling) return;
        if (Board == null && Sea.IsInsideTree())
        {
            if (shownReach != Watch.Index) { foreach (var old in hulls) old.QueueFree(); hulls.Clear(); foreach (var c in Watch.Contacts) { var hull = PrizeArt.Contact(c); Sea.AddChild(hull); hulls.Add(hull); } shownReach = Watch.Index; }
            for (int i = 0; i < Math.Min(hulls.Count, Watch.Contacts.Length); i++)
            {
                var c = Watch.Contacts[i]; var hull = hulls[i];
                hull.Visible = Watch.Phase is PrizePhase.Search or PrizePhase.Hail or PrizePhase.Chase or PrizePhase.Witness && !c.Released;
                hull.Position = NativeStage3D.Point(c.Position, .02f * MathF.Sin(clock * 1.8f + i)); hull.Rotation = new(0, -MathF.Atan2(c.Bow.X, -c.Bow.Y), 0);
            }
            DrawInquest();
            packet!.Visible = Watch.Phase is PrizePhase.Witness or PrizePhase.Return; packet.Position = NativeStage3D.Point(Watch.Phase == PrizePhase.Return ? Watch.Exit : Watch.Witness);
            stores!.Visible = !Watch.Foraged && Watch.Phase is PrizePhase.Witness or PrizePhase.Search or PrizePhase.Chase; stores.Position = NativeStage3D.Point(Watch.Cache);
            flag!.Visible = Watch.Phase == PrizePhase.Return && Watch.ReturnGate < Watch.Gates.Length; if (flag.Visible) flag.Position = NativeStage3D.Point(Watch.Destination);
            prize!.Visible = Watch.HasFinalTow; if (prize.Visible) { prize.Position = NativeStage3D.Point(Watch.Tow); var tow = Watch.Ship.Position - Watch.Tow; prize.Rotation = new(0, -MathF.Atan2(tow.X, -tow.Y), 0); }
        }
        string state = manualChart ? "chart" : Watch.Phase == PrizePhase.Won || Watch.Phase == PrizePhase.Lost ? "result" : stageChoice ? "stage" :
            Board == null && Watch.Ship.Mode == VoyageMode.Upgrade ? "guns" : Watch.Phase is PrizePhase.Muster or PrizePhase.Hail or PrizePhase.Refit ? Watch.Phase.ToString() : "";
        string key = state == "" ? "" : $"{state}/{Watch.Index}/{Watch.Queried?.Name}/{Watch.Ship.PendingUpgrades}";
        if (menuKey != key) { CloseSheet(); menuKey = key; if (state != "") Sheet(state); }
        hud.QueueRedraw();
    }
    void DrawInquest()
    {
        var inquiry = Watch.Phase == PrizePhase.Inquiry ? Watch.Inquiry : null;
        rival!.Visible = inquiry is { RivalOn: true };
        if (rival.Visible) { rival.Position = NativeStage3D.Point(inquiry!.Rival); rival.Rotation = new(0, -MathF.Atan2(inquiry.RivalBow.X, -inquiry.RivalBow.Y), 0); }
        int shown = 0;
        var sites = inquiry?.Sites() ?? (Watch.Phase == PrizePhase.Assize ? Watch.Assize?.Sites() : null);
        if (sites != null) foreach (var site in sites)
        {
            if (shown >= inquestProps.Count || inquestProps[shown].Kind != site.Kind)
            {
                var model = site.Kind == "court" ? PrizeArt.Court(Watch.Country) : BluewaterArt.Prop(Watch.Country, site.Kind); Sea.AddChild(model);
                if (shown == inquestProps.Count) inquestProps.Add((site.Kind, model));
                else { inquestProps[shown].Model.QueueFree(); inquestProps[shown] = (site.Kind, model); }
            }
            var prop = inquestProps[shown++].Model; prop.Visible = true; prop.Position = NativeStage3D.Point(site.Point);
        }
        for (int i = shown; i < inquestProps.Count; i++) inquestProps[i].Model.Visible = false;
    }
    void CloseSheet()
    {
        if (sheet != null) { canvas.RemoveChild(sheet); sheet.QueueFree(); sheet = null; }
        choices.Clear(); menuKey = "";
    }
    void Sheet(string state)
    {
        sheet = new ColorRect { Color = new Color("0d223ab8"), MouseFilter = Control.MouseFilterEnum.Stop }; canvas.AddChild(sheet); sheet.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        var center = new CenterContainer(); sheet.AddChild(center); center.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        var panel = new PanelContainer { CustomMinimumSize = new(690, 0) }; panel.AddThemeStyleboxOverride("panel", HarborType.Box(new("18323e"), new(Watch.Country.Accent), 23, 17)); center.AddChild(panel);
        var box = new VBoxContainer(); box.AddThemeConstantOverride("separation", 9); panel.AddChild(box);
        void Text(string s, int n = 18, bool heading = false) => box.AddChild(HarborType.Text(s, n, heading ? HarborType.Cream : HarborType.Brass, heading));
        void Pick(string label, Action act)
        {
            int num = choices.Count + 1; void Go() { if (exiting) return; act(); if (!exiting) Render(); }
            var btn = HarborType.Button($"{num}    {label}", Go, num == 1); box.AddChild(btn); choices.Add(Go); if (num == 1) btn.GrabFocus();
        }
        Text($"{Watch.RegionName.ToUpperInvariant()}     /     PRIZE WATCH", 14);
        if (state == "result")
        {
            bool win = Watch.Phase == PrizePhase.Won; Text(win ? "The prize makes harbor" : "The watch comes home", 32, true);
            Text(win ? Order.Homecoming : Watch.Dispatch); if (win && Watch.Found) Text(Watch.Exhibit.Finding); Text($"{SilverAboard} silver aboard"); Pick("Return to " + LandingName, () => { exiting = true; if (Returned != null) Returned(win, SilverEarned); else GetTree().ChangeSceneToFile("res://main.tscn"); }); return;
        }
        if (state == "Muster")
        {
            Text(Order.Title, 30, true); Text(Order.Brief); Text(Order.Objective); Text("Choose the first watch", 19, true);
            Pick("Carpenter’s watch   ·   An extra repair kit", () => { shownReach = -1; Watch.Start(0); });
            Pick("Gunner’s watch   ·   Rigging tools and faster reload", () => { shownReach = -1; Watch.Start(1); });
            Pick("Pilot’s watch   ·   A witness aboard and an allied boat", () => { shownReach = -1; Watch.Start(2); }); return;
        }
        if (state == "Hail")
        {
            Text(Watch.Queried!.Name, 27, true); Text(Watch.Queried.Marks); if (Watch.Queried == Watch.Mark && Watch.Dockets > 0) Text($"The manifest lists {Watch.Exhibit.Item}. The examiner recorded {Watch.Exhibit.Mark}."); Text($"Pilot’s report    {Watch.PublicClue}  Reply with {PrizeTheater.Calls[Watch.CorrectCall]}.");
            for (int i = 0; i < 3; i++) { int call = i; Pick("Answer with " + PrizeTheater.Calls[i], () => Watch.Hail(call)); }
            Pick("Order her to strike sail", () => Watch.Hail(3)); Pick("Break away and keep looking", () => Watch.Hail(4)); Pick("Issue a civilian passage flag", () => Watch.Hail(5)); return;
        }
        if (state == "stage")
        {
            bool land = Watch.Phase == PrizePhase.Landfall;
            if (Watch.CommissionLeg != 0)
            {
                Text(land ? "The depot’s second copy" : "A counterclaim on the cargo", 27, true);
                Text(land ? Watch.CommissionPort(false).Objective : Watch.CommissionPassage(false).Brief);
                Pick(land ? "Take the clerk through the infirmary" : "Lift the receiver’s counterclaim", () => StartStage(false));
                Pick(land ? "Take the upper yard before the accounts burn" : "Break the bonded convoy", () => StartStage(true)); return;
            }
            Text(land ? "At the signal steps" : "The relief convoy", 27, true);
            Text(land ? "The shore party can carry the civilian signaler out, or climb to the warning drum and steal the original stamp." : "The pilots across the reach can shelter the witnesses, or help you break the customs booms in their wake.");
            Pick(land ? "Bring out the signaler" : "Escort the witness boats", () => StartStage(false));
            Pick(land ? "Take the exposed signal arm" : "Break the examination line", () => StartStage(true)); return;
        }
        if (state == "guns")
        {
            Text("A fitting for the next engagement", 25, true);
            for (int i = 0; i < Watch.Ship.UpgradeChoices.Count; i++) { int fit = i, v = Watch.Ship.UpgradeChoices[i]; Pick(Voyage.UpgradeNames[v] + "   ·   " + Watch.Ship.UpgradeBenefit(v), () => Watch.Upgrade(fit)); }
            if (choices.Count == 0) Pick("Repair the hull", () => Watch.Upgrade(0)); return;
        }
        if (state == "chart")
        {
            Text(Order.Title, 27, true); Text(string.Join("   ›   ", Watch.Operations.Select((op, i) => i < Watch.Index ? "✓ " + op.ToString() : op.ToString()))); Text(Order.Objective);
            if (Watch.Report > 0) Text($"Marks    {Watch.PublicClue}    Reply    {PrizeTheater.Calls[Watch.CorrectCall]}");
            Text(Watch.Found ? Watch.Exhibit.Finding : "The order names " + Watch.Exhibit.Item + ".");
            Text($"Evidence {Watch.Evidence}   ·   People brought out {Watch.Prisoners}   ·   Allied boats {Watch.Allies}   ·   Alarm {Watch.Alarm}");
            Pick("Return to the helm", () => manualChart = false); Pick("Withdraw with this watch’s silver", () => { manualChart = false; Watch.Withdraw(); }); return;
        }
        Text(Watch.WatchName + " is clear", 27, true); Text($"Hull {Watch.Ship.Health:0} / {Watch.Ship.MaxHealth:0}     Crew strain {Watch.Strain}     Silver aboard {SilverAboard}");
        Pick("Mend the cutter and tend the watch   ·   +29 hull, a kit and rest", () => Watch.Refit(0));
        Pick("Fit a second purchase   ·   Faster gun and line, louder squadron", () => Watch.Refit(1));
        Pick("Recruit pilots   ·   More witnesses, lower alarm", () => Watch.Refit(2));
        if (Watch.CommissionAvailable)
        {
            Text($"A second declaration for {Watch.Exhibit.Item} is still in bond. The tender and shore depot will provide a duplicate for the hearing.", 16);
            Pick("Press the counterclaim   ·   Optional convoy and depot, two allied pilots", () => { Watch.AcceptCommission(); stageChoice = true; });
        }
        else if (Watch.CommissionWon) Text("The two signed accounts are ready for the public hearing.", 16);
    }
}
