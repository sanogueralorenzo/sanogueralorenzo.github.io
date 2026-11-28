using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

public partial class Game : Node
{
    readonly HarborSave journal = new();
    HarborLedger ledger = new();
    Node? location;
    Passage passage;
    CampaignOrder? order;
    CanvasLayer? pause;
    bool returning, usedKeepsake, logUnavailable;
    TideScore score=null!;
    int harborRegion;
    ulong closingAfter;
    WatchClock? watchClock;

    public override void _Ready()
    {
        GetTree().AutoAcceptQuit=false;
        GetWindow().Title = "Boats ’n’ Beasts  ·  The Silent Watch";
        try { ledger = journal.Open(); }
        catch (Exception error) { ShowError(error); return; }
        watchClock=new(ledger.Hours);
        score=new(){Hear=ListenToWatch};AddChild(score);
        if(journal.Interrupted)Harbor("The night tender made it home",$"Nell brought {journal.Recovered} silver ashore from the interrupted run. The crew has put the unfinished order back on the chart.");
        else Harbor();
    }
    (int Region,WatchTempo Tempo) ListenToWatch()
    {
        var where=location is CrewRun run?run.InPlay:location;
        var tempo = pause!=null ? WatchTempo.Harbor : where switch
        {
            BluewaterVoyage sea when sea.Course.Phase==ChartPhase.Boss => WatchTempo.Danger,
            FlotillaCommand fleet when fleet.Battle.Field==FleetField.Captain=>WatchTempo.Danger,
            MusterLanding muster when muster.Muster.Phase==MusterPhase.Guard=>WatchTempo.Danger,
            KilnExpedition foot when foot.Yard.Phase==YardPhase.Guardian => WatchTempo.Danger,
            UnderwaysExpedition crawl when crawl.Crawl.Surface?.Phase==YardPhase.Guardian ||
                crawl.Crawl.Surface==null && crawl.Crawl.Room.Trial==UnderTrial.Keeper && !crawl.Crawl.Quiet => WatchTempo.Danger,
            PrizeWatch prize when prize.Board!=null => WatchTempo.Landing,
            ShoreExpedition shore when shore.Fight.Phase==QuayPhase.Warden => WatchTempo.Danger,
            SeaPassage sails when sails.Run.Leg==PassageLeg.Keelwidow => WatchTempo.Danger,
            KilnExpedition or ShoreExpedition or UnderwaysExpedition => WatchTempo.Landing,
            MusterLanding=>WatchTempo.Landing,
            NightPostWatch or FlotillaWatch=>WatchTempo.Harbor,
            CrewRun => WatchTempo.Sailing,
            _ => WatchTempo.Harbor
        };
        return (order==null ? harborRegion : order.Tier-1,tempo);
    }
    public override void _ExitTree()
    {
        try { if(watchClock!=null && !logUnavailable)journal.Write(ledger with{Hours=watchClock.Hours}); }
        finally { journal.Dispose(); }
    }
    public override void _Input(InputEvent input)
    {
        if(input is InputEventKey { Pressed:true } or InputEventMouseButton { Pressed:true } or InputEventMouseMotion
            or InputEventJoypadButton {Pressed:true} or InputEventJoypadMotion)watchClock?.Touch();
    }

    void Save(HarborLedger next)
    {
        try
        {
            if(watchClock!=null)
            {
                if(next.Campaign.StoryCleared)watchClock.Finish();
                next=next with{Hours=watchClock.Hours};
            }
            journal.Write(next);ledger=next;watchClock?.Filed();
        }
        catch (Exception error) { ShowError(error); throw; }
    }
    void ShowError(Exception error)
    {
        logUnavailable=true;
        GD.PushError(error.Message);
        GetTree().Paused = true;
        var warning = new AcceptDialog { Title = "Harbor log unavailable",
            DialogText = "The harbor log could not be opened or written. Check the save file and available disk space.\n\n" + error.Message,
            ProcessMode = ProcessModeEnum.Always };
        AddChild(warning); warning.Confirmed += () => GetTree().Quit();
        warning.PopupCentered(new(630, 245));
    }
    void ClearLocation()
    {
        if (location == null) return;
        RemoveChild(location); location.QueueFree(); location = null;
    }
    void Harbor(string heading = "", string message = "",CampaignOrder? delivered = null)
    {
        ClearLocation(); order = null;
        harborRegion=ledger.Campaign.Next?.Arc.Orders[0].Tier-1 ?? 15;
        GetWindow().Title = ledger.Campaign.HomePortNamed ? "Boats ’n’ Beasts  ·  The Walking Tide" : ledger.Dedicated ? "Boats ’n’ Beasts  ·  The Far Ledger" : "Boats ’n’ Beasts  ·  The Silent Watch";
        location = new LastLightHarbor { Ledger = ledger, Changed = Save, Depart = Embark, AcceptOrder = Embark, Score=score, Clockbook=watchClock,
            ReturnHeading = heading, ReturnMessage = message, Delivered = delivered };
        AddChild(location); returning = false;
    }
    void Embark(Passage route)
    {
        if (location is not LastLightHarbor || route == Passage.BellwetherQuay && !ledger.HasTongue) return;
        watchClock?.Depart();Save(ledger);passage = route;
        int seed = Random.Shared.Next();
        ClearLocation();
        location = route == Passage.LanternSound
            ? new SeaPassage { Seed = seed, Stores = ledger.Stores, Returned = Land }
            : new ShoreExpedition { Seed = seed, Stores = ledger.Stores, Returned = Land };
        AddChild(location);
    }
    void Embark(CampaignOrder requested)
    {
        if (location is not LastLightHarbor || !ledger.Dedicated) return;
        if (!ledger.Campaign.Available().Any(o => o.Id == requested.Id) && !ledger.Campaign.Contains(requested.Id)) return;
        watchClock?.Depart();Save(ledger);usedKeepsake=false;order = requested;
        int seed = Random.Shared.Next();
        ClearLocation();
        CrewRun run=requested switch
        {
            { Flotilla:true }=>new FlotillaWatch{Order=requested},
            { PrizeWatch:true }=>new PrizeWatch {Order=requested},
            { Underways:true }=>new UnderwaysExpedition {Order=requested},
            { Postal:true }=>new NightPostWatch {Order=requested},
            { Migration:true }=>new MigrationWatch {Order=requested},
            { Pilotage:true }=>new PilotageVoyage {Order=requested},
            { Ashore:true }=>new KilnExpedition {Order=requested},
            _=>new BluewaterVoyage {Order=requested}
        };
        run.Seed=seed;run.Stores=ledger.Stores;run.Outfit=ledger.Outfit;run.Returned=Land;
        run.Vessel=ledger.Vessel;run.Figurehead=ledger.Figurehead;
        location=run;AddChild(run);
    }
    int Purse => location is CrewRun run ? run.SilverEarned : 0;
    public override void _Process(double delta)
    {
        if(closingAfter!=0)
        {
            if(Time.GetTicksMsec()>=closingAfter)GetTree().Quit();
            return;
        }
        if(Input.IsAnythingPressed())watchClock?.Touch();
        watchClock?.Tick(location is CrewRun,location!=null && pause==null && GetWindow().HasFocus());
        if (location is not CrewRun || returning) {if(watchClock?.Due==true)Save(ledger);return;}
        CheckpointPurse();
    }
    void CheckpointPurse()
    {
        int earned = Purse;
        if (earned != ledger.AtSea || watchClock?.Due==true) Save(ledger with { AtSea = earned });
    }
    void Land(bool won, int earned)
    {
        if (returning || location is not CrewRun) return;
        returning = true;watchClock?.Land(won);
        var missed=won ? default : ReturnWatch.Unfinished((CrewRun)location,order);
        if (order != null)
        {
            bool recollection = ledger.Campaign.Contains(order.Id);
            var next = ledger.Bank(earned);
            if (won) next = next with { Campaign = next.Campaign.File(order,(location as FlotillaWatch)?.Passage.Pledge) };
            Save(next);
            string report = !won ? missed.Story : recollection ? "The crew folds away the old chart and counts the salvage." : next.Campaign.Homecoming(order);
            string title = won ? order.Title : missed.Heading;
            var delivered=won && !recollection ? order : null;
            Callable.From(() => Harbor(title, $"{report}   Banked {earned} silver.",delivered)).CallDeferred();
            return;
        }
        bool newTongue = won && passage == Passage.LanternSound && !ledger.HasTongue;
        bool newBell = won && passage == Passage.BellwetherQuay && !ledger.BellReleased;
        Save(ledger.Land(passage, won, earned));
        string heading = !won ? missed.Heading : newTongue ? "Bronze in the bilge" : newBell ? "The last keeper comes home" : "Safe in the lee";
        string story = !won ? missed.Story
            : newTongue ? "Vara lifts the tongue from its sling. The tide marks cut into the bronze lead to Bellwether Quay. Its landing is open."
            : newBell ? "Nell Spindle steps onto the planks, her ledger wrapped in oilcloth. Vara and Lio lift the bell onto its waiting frame. Meet them at the crew table."
            : "The crew splits the watch while you tally the salvage.";
        Callable.From(() => Harbor(heading, $"{story}   Banked {earned} silver.")).CallDeferred();
    }
    public override void _UnhandledKeyInput(InputEvent input)
    {
        if(input is InputEventKey { Keycode: Key.F, Pressed:true, Echo:false } && !returning && pause==null && order!=null &&
            !usedKeepsake && ledger.Campaign.OnWatch!=Shipmate.None && location is CrewRun watch)
        {
            usedKeepsake=watch.AskShipmate(ledger.Campaign.OnWatch);
            if(usedKeepsake)GetViewport().SetInputAsHandled();
            return;
        }
        if (input is not InputEventKey { Keycode: Key.Escape, Pressed: true, Echo: false } || returning ||
            location is not CrewRun) return;
        if (pause == null) Hold(); else Resume();
        GetViewport().SetInputAsHandled();
    }
    public override void _Notification(int what)
    {
        if(what==NotificationWMCloseRequest)
        {
            if(closingAfter!=0)return;
            if(watchClock==null || logUnavailable){GetTree().Quit();return;}
            if(location is CrewRun && !returning)CheckpointPurse();
            closingAfter=Time.GetTicksMsec()+110;
            if(location!=null)location.ProcessMode=ProcessModeEnum.Disabled;
            foreach(var voice in FindChildren("*","AudioStreamPlayer",true,false).OfType<AudioStreamPlayer>())voice.Stop();
            if(score!=null)score.SetProcess(false);
            return;
        }
        if (location is not CrewRun || returning || closingAfter!=0) return;
        if (what == NotificationApplicationFocusOut && pause == null)
        {
            var interrupted = location;
            Callable.From(() =>
            {
                if (location == interrupted && !returning && pause == null && !GetWindow().HasFocus()) Hold();
            }).CallDeferred();
        }
    }
    void Hold(bool instructions=false)
    {
        if (location == null) return;
        location.ProcessMode = ProcessModeEnum.Disabled;
        pause = new CanvasLayer { Layer = 15 }; AddChild(pause);
        var shade = new ColorRect { Color = new Color("0b2435bd") }; pause.AddChild(shade);
        shade.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        var center = new CenterContainer(); shade.AddChild(center); center.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        var panel = new PanelContainer(); panel.AddThemeStyleboxOverride("panel", HarborType.Box(new("17323f"), HarborType.Brass, 28, 22)); center.AddChild(panel);
        var column = new VBoxContainer(); column.AddThemeConstantOverride("separation",12); panel.AddChild(column);
        column.AddChild(HarborType.Text(instructions?"Orders and controls":"At anchor",36,HarborType.Cream,true));
        if(instructions)
        {
            panel.CustomMinimumSize=new(580,0);
            column.AddChild(HarborType.Text(WatchInstructions.For(location as CrewRun),21,HarborType.Cream));
            var again=HarborType.Button("Back",()=>{Resume();Hold();},true);column.AddChild(again);again.GrabFocus();return;
        }
        column.AddChild(HarborType.Text($"{Purse} silver aboard", 20, HarborType.Brass));
        if(order!=null && ledger.Campaign.OnWatch is not Shipmate.None)
            column.AddChild(HarborType.Text(CrewWatches.Token(ledger.Campaign.OnWatch)+(usedKeepsake?"   ·   Used this run":"   ·   Press F during play"),17,HarborType.Teal));
        var resume = HarborType.Button("Resume", Resume, true); column.AddChild(resume);
        column.AddChild(HarborType.Button("Retreat and bank the silver", () => { int earned = Purse; Resume(); Land(false, earned); }));
        column.AddChild(HarborType.Button("Orders and controls",()=>{Resume();Hold(true);}));
        var music=HarborType.Button(score.Quiet?"Music off":"Music on",()=>{score.Toggle();Resume();Hold();});
        column.AddChild(music);resume.GrabFocus();
    }
    void Resume()
    {
        if (pause == null || location == null) return;
        RemoveChild(pause); pause.QueueFree(); pause = null; location.ProcessMode = ProcessModeEnum.Inherit;
    }
}
