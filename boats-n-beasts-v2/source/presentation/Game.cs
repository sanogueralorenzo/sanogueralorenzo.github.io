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
    bool returning;

    public override void _Ready()
    {
        GetWindow().Title = "Boats ’n’ Beasts  ·  The Silent Watch";
        try { ledger = journal.Open(); }
        catch (Exception error) { ShowError(error); return; }
        Harbor();
    }
    public override void _ExitTree() => journal.Dispose();

    void Save(HarborLedger next)
    {
        try { journal.Write(next); ledger = next; }
        catch (Exception error) { ShowError(error); throw; }
    }
    void ShowError(Exception error)
    {
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
    void Harbor(string heading = "", string message = "")
    {
        ClearLocation(); order = null;
        GetWindow().Title = ledger.Dedicated ? "Boats ’n’ Beasts  ·  The Far Ledger" : "Boats ’n’ Beasts  ·  The Silent Watch";
        location = new LastLightHarbor { Ledger = ledger, Changed = Save, Depart = Embark, AcceptOrder = Embark,
            ReturnHeading = heading, ReturnMessage = message };
        AddChild(location); returning = false;
    }
    void Embark(Passage route)
    {
        if (location is not LastLightHarbor || route == Passage.BellwetherQuay && !ledger.HasTongue) return;
        passage = route;
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
        if (!ledger.Campaign.Available().Any(o => o.Id == requested.Id) && !ledger.Campaign.Voyages.Contains(requested.Id)) return;
        order = requested;
        int seed = Random.Shared.Next();
        ClearLocation();
        location = requested.Ashore
            ? new KilnExpedition { Order = requested, Seed = seed, Stores = ledger.Stores, Outfit = ledger.Outfit, Returned = Land }
            : new BluewaterVoyage { Order = requested, Seed = seed, Stores = ledger.Stores, Outfit = ledger.Outfit, Returned = Land };
        AddChild(location);
    }
    int Purse => location is CrewRun run ? run.SilverEarned : 0;
    public override void _Process(double delta)
    {
        if (location is not CrewRun || returning) return;
        CheckpointPurse();
    }
    void CheckpointPurse()
    {
        int earned = Purse;
        if (earned != ledger.AtSea) Save(ledger with { AtSea = earned });
    }
    void Land(bool won, int earned)
    {
        if (returning || location is not CrewRun) return;
        returning = true;
        if (order != null)
        {
            bool recollection = ledger.Campaign.Voyages.Contains(order.Id);
            var next = ledger.Bank(earned);
            if (won) next = next with { Campaign = next.Campaign.File(order) };
            Save(next);
            string report = recollection ? "The crew folds away the old chart and counts the salvage." : won ? order.Homecoming : $"The crew makes it back with the purse. The order for {order.Region} is still on the chart.";
            string title = won ? order.Title : "The unfinished crossing";
            Callable.From(() => Harbor(title, $"{report}   Banked {earned} silver.")).CallDeferred();
            return;
        }
        bool newTongue = won && passage == Passage.LanternSound && !ledger.HasTongue;
        bool newBell = won && passage == Passage.BellwetherQuay && !ledger.BellReleased;
        Save(ledger.Land(passage, won, earned));
        string heading = !won ? "Back on the planks" : newTongue ? "Bronze in the bilge" : newBell ? "The last keeper comes home" : "Safe in the lee";
        string story = !won ? "Lio counts heads first. The crew dries its gear for another attempt."
            : newTongue ? "Vara lifts the tongue from its sling. The tide marks cut into the bronze lead to Bellwether Quay. Its landing is open."
            : newBell ? "Nell Spindle steps onto the planks, her ledger wrapped in oilcloth. Vara and Lio lift the bell onto its waiting frame. Meet them at the crew table."
            : "The crew splits the watch while you tally the salvage.";
        Callable.From(() => Harbor(heading, $"{story}   Banked {earned} silver.")).CallDeferred();
    }
    public override void _UnhandledKeyInput(InputEvent input)
    {
        if (input is not InputEventKey { Keycode: Key.Escape, Pressed: true, Echo: false } || returning ||
            location is not CrewRun) return;
        if (pause == null) Hold(); else Resume();
        GetViewport().SetInputAsHandled();
    }
    public override void _Notification(int what)
    {
        if (location is not CrewRun || returning) return;
        if (what == NotificationWMCloseRequest) CheckpointPurse();
        if (what == NotificationApplicationFocusOut && pause == null)
        {
            var interrupted = location;
            Callable.From(() =>
            {
                if (location == interrupted && !returning && pause == null && !GetWindow().HasFocus()) Hold();
            }).CallDeferred();
        }
    }
    void Hold()
    {
        if (location == null) return;
        location.ProcessMode = ProcessModeEnum.Disabled;
        pause = new CanvasLayer { Layer = 15 }; AddChild(pause);
        var shade = new ColorRect { Color = new Color("0b2435bd") }; pause.AddChild(shade);
        shade.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        var center = new CenterContainer(); shade.AddChild(center); center.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        var panel = new PanelContainer(); panel.AddThemeStyleboxOverride("panel", HarborType.Box(new("17323f"), HarborType.Brass, 28, 22)); center.AddChild(panel);
        var column = new VBoxContainer(); column.AddThemeConstantOverride("separation",12); panel.AddChild(column);
        column.AddChild(HarborType.Text("At anchor", 36, HarborType.Cream, true));
        column.AddChild(HarborType.Text($"{Purse} silver aboard", 20, HarborType.Brass));
        var resume = HarborType.Button("Resume", Resume, true); column.AddChild(resume);
        column.AddChild(HarborType.Button("Retreat and bank the silver", () => { int earned = Purse; Resume(); Land(false, earned); }));
        resume.GrabFocus();
    }
    void Resume()
    {
        if (pause == null || location == null) return;
        RemoveChild(pause); pause.QueueFree(); pause = null; location.ProcessMode = ProcessModeEnum.Inherit;
    }
}
