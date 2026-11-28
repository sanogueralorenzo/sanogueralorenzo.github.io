using BoatsNBeasts.Core;
using Godot;
using static BoatsNBeasts.HarborType;

namespace BoatsNBeasts;

internal partial class LastLightHarbor : Node
{
    internal HarborLedger Ledger = new();
    internal Action<Passage>? Depart;
    internal Action<HarborLedger>? Changed;
    internal string ReturnHeading = "", ReturnMessage = "";
    QuayView quay = null!;
    QuayMusic music = null!;
    CanvasLayer canvas = null!;
    Control ui = null!;
    PanelContainer? sheet;
    RouteChart? chartMap;
    HBoxContainer choices = null!;
    Label money = null!, direction = null!;
    readonly Dictionary<WharfStop, Button> markers = [];
    int crewLine;
    string status = "";

    public override void _Ready()
    {
        AddQuay();
        music = new(); AddChild(music);
        canvas = new(); AddChild(canvas);
        ui = new Control { MouseFilter = Control.MouseFilterEnum.Ignore };
        canvas.AddChild(ui); ui.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        var masthead = Masthead();
        var titles = new VBoxContainer(); masthead.AddChild(titles);
        titles.AddChild(Text("BOATS ’N’ BEASTS", 16, Brass));
        titles.AddChild(Text("Last Light Quay", 39, Cream, true));
        money = Text("", 19, Brass);
        var purse = new PanelContainer { AnchorLeft = 1, AnchorRight = 1, OffsetLeft = -225, OffsetRight = -24, OffsetTop = 24 };
        purse.AddThemeStyleboxOverride("panel", Box(new("152e3af6"), new("bb996c"))); ui.AddChild(purse);
        money.HorizontalAlignment = HorizontalAlignment.Center;
        purse.AddChild(money);
        string[] names = ["Crew table", "Galley", "Chart a course", "Nell Spindle"];
        foreach (var stop in quay.OpenStations)
        {
            var marker = Button(names[(int)stop], () => quay.WalkTo(stop), stop == WharfStop.Berth);
            marker.AccessibilityName = names[(int)stop];
            ui.AddChild(marker);
            markers[stop] = marker;
        }
        var guide = new PanelContainer { AnchorTop = 1, AnchorBottom = 1, OffsetLeft = 24, OffsetRight = 798, OffsetTop = -104, OffsetBottom = -22 };
        guide.AddThemeStyleboxOverride("panel", Box(new("122f3bf0"), new("987c5f"))); ui.AddChild(guide);
        var column = new VBoxContainer(); guide.AddChild(column);
        direction = Text("", 22, Cream, true); column.AddChild(direction);
        column.AddChild(Text("Click a station   ·   WASD to walk   ·   E to interact", 16, Teal));
        RefreshLedger();
        if (ReturnHeading.Length > 0)
        {
            Open("SHIP’S LOG", ReturnHeading, ReturnMessage);
            Choice("Step onto the quay", Close, true);
        }
    }

    void AddQuay()
    {
        quay = new QuayView { Ledger = Ledger, Arrived = Visit };
        AddChild(quay);
    }
    void UpdateLedger(HarborLedger next)
    {
        Changed?.Invoke(next); Ledger = next;
        RemoveChild(quay); quay.QueueFree(); AddQuay(); quay.Exploring = sheet == null;
        RefreshLedger();
    }
    void RefreshLedger()
    {
        money.Text = $"{Ledger.Silver} silver   ·   Bank";
        direction.Text = Ledger.Dedicated ? Ledger.Campaign.NeedsHearing ? "Hear the witnesses at the crew table."
            : Ledger.Campaign.Current is { } next ? $"At the chart   ·   {next.Region}, {next.Title}" : "The quay rings again." : Ledger.BellReleased ? "Join the crew at the table for the first ringing."
            : Ledger.HasTongue ? "Carry the bell tongue ashore at Bellwether." : "Three skiffs went into the fog. Two came home. Ask the crew.";
    }
    public override void _Process(double delta)
    {
        foreach (var stop in quay.OpenStations)
        {
            var marker = markers[stop];
            marker.Position = quay.Marker(stop) - new Vector2(marker.Size.X / 2, 0);
        }
    }
    public override void _UnhandledKeyInput(InputEvent input)
    {
        if (input is not InputEventKey { Pressed: true, Echo: false } key) return;
        if (key.Keycode == Key.Escape && sheet != null) Close();
        else if (key.Keycode == Key.E && sheet == null) quay.Hail();
        else return;
        GetViewport().SetInputAsHandled();
    }
    PanelContainer Masthead()
    {
        var panel = new PanelContainer { OffsetLeft = 24, OffsetRight = 376, OffsetTop = 24 };
        panel.AddThemeStyleboxOverride("panel", Box(new("102c38f7"), new("a38c66")));
        ui.AddChild(panel); return panel;
    }
    void Close()
    {
        if (chartMap != null) { ui.RemoveChild(chartMap); chartMap.QueueFree(); chartMap = null; }
        if (sheet != null) { ui.RemoveChild(sheet); sheet.QueueFree(); sheet = null; }
        quay.Exploring = true;
        foreach (var marker in markers.Values) marker.Show();
        status = "";
    }
    void Open(string byline, string heading, string body)
    {
        Close(); quay.Exploring = false;
        foreach (var marker in markers.Values) marker.Hide();
        sheet = new PanelContainer { AnchorTop = 1, AnchorBottom = 1, AnchorRight = 1,
            GrowVertical = Control.GrowDirection.Begin, OffsetLeft = 24, OffsetRight = -24, OffsetTop = -232, OffsetBottom = -22 };
        sheet.AddThemeStyleboxOverride("panel", Box(new("112c39fd"), new("d8ad76"), 25, 12)); ui.AddChild(sheet);
        var col = new VBoxContainer(); sheet.AddChild(col);
        col.AddThemeConstantOverride("separation", 5);
        col.AddChild(Text(byline, 16, Teal));
        col.AddChild(Text(heading, 31, Brass, true));
        col.AddChild(Text(body, 22, Cream));
        choices = new HBoxContainer { SizeFlagsVertical = Control.SizeFlags.ExpandFill, Alignment = BoxContainer.AlignmentMode.Begin };
        choices.AddThemeConstantOverride("separation", 12); col.AddChild(choices);
    }
    void Choice(string text, Action action, bool primary = false)
    {
        var button = Button(text, action, primary);
        button.SizeFlagsVertical = Control.SizeFlags.ShrinkEnd; choices.AddChild(button);
        if (choices.GetChildCount() == 1) button.CallDeferred(Control.MethodName.GrabFocus);
    }
    void Visit(WharfStop stop)
    {
        switch (stop)
        {
            case WharfStop.Crew: Crew(); break;
            case WharfStop.Galley: Galley(); break;
            case WharfStop.Berth: Chart(); break;
            case WharfStop.Belfry: Keeper(); break;
        }
    }
    void Chart()
    {
        if (Ledger.Dedicated) { FarChart(); return; }
        if (Ledger.HasTongue)
        {
            Open("THE SOUNDINGS   /   CHAPTER I", "Bellwether Quay", Ledger.BellReleased
                ? "The watch has changed. Return for salvage with the crew or follow the wreck trail back into Lantern Sound."
                : "Lio has tied the tongue into his sling. Dock below the belfry, work the signal bells and break the Bellwarden’s watch.");
            Choice("Go ashore at Bellwether", () => Depart?.Invoke(Passage.BellwetherQuay), true);
            Choice("Sail Lantern Sound", () => Depart?.Invoke(Passage.LanternSound));
        }
        else
        {
            Open("THE SOUNDINGS   /   CHAPTER I", "Lantern Sound", "Something with a shipwreck on its back is dragging the bell tongue through the shoals. Bring it home before the next fog.");
            Choice("Set sail", () => Depart?.Invoke(Passage.LanternSound), true);
        }
        Choice("Back to the quay", Close);
    }
    void Galley()
    {
        string detail = Ledger.Stores switch
        {
            0 => "Vara has room for a broth pot and hull patches. Fit the galley to start sea and shore runs with more health.",
            1 => "A lidded stove will keep the broth hot all the way to Bellwether. The second fitting increases starting health again.",
            _ => "Two pots swing level in their brass cradles. The crew has a hot meal and a full hull for every departure."
        };
        string message = status;
        Open("PROVISIONS", "The swinging stove", message.Length > 0 ? message + "  " + detail : detail);
        if (Ledger.Stores < 2)
        {
            int cost = Ledger.StoreCost;
            Choice($"Fit the galley   ·   {cost} silver", () =>
            {
                var next = Ledger.FitGalley();
                if (next == Ledger) { status = $"The bank needs {cost - Ledger.Silver} more silver."; Galley(); return; }
                UpdateLedger(next); status = "The new fitting is ready."; Galley();
            }, true);
        }
        if (Ledger.Dedicated) Choice("Visit the outfitter", Outfitter);
        Choice("Back to the quay", Close);
    }

    void Outfitter()
    {
        var rig = Shipyard.Plans.First(p => p.Kit == Ledger.Outfit);
        Open("THE OUTFITTER", "Fit out the crew", $"{rig.Name} is equipped for charted journeys. Purchased patterns can be refitted freely.");
        foreach (var plan in Shipyard.Plans)
            Choice(plan.Name, () =>
            {
                bool owned = plan.Kit == Loadout.Standard || Ledger.Patterns.Contains(plan.Kit);
                string price = owned ? "Pattern on file." : $"Pattern costs {plan.Silver} silver.";
                Open("CREW PATTERN",plan.Name,$"{plan.Description}  {price}");
                if (owned || Ledger.Silver >= plan.Silver) Choice(owned ? "Equip this rig" : "Buy and equip", () =>
                {
                    UpdateLedger(Ledger.Equip(plan)); Outfitter();
                },true);
                else Choice($"Need {plan.Silver - Ledger.Silver} more silver",Outfitter);
                Choice("Other patterns",Outfitter);
            }, plan.Kit == Ledger.Outfit);
        Choice("Back to the quay",Close);
    }
}
