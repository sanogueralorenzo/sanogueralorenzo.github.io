namespace BoatsNBeasts.Core;

public sealed partial class PrizeTheater
{
    public int CommissionLeg { get; private set; }
    public bool CommissionWon { get; private set; }
    public bool CommissionAvailable => Phase == PrizePhase.Refit && Index < Operations.Length - 1 && !CommissionWon && CommissionLeg == 0;
    public void AcceptCommission()
    {
        if (!CommissionAvailable) return;
        CommissionLeg = 1; Phase = PrizePhase.Crossing;
        Say("The counterclaim is open. Intercept its tender, then take the sealed account into the bonded depot.");
    }
    bool SettleCommission(PrizePhase completed, float strength)
    {
        if (CommissionLeg == 0) return false;
        if (completed == PrizePhase.Crossing)
        {
            Ship.Health = Math.Max(1, Ship.MaxHealth * strength); CommissionLeg = 2;
            Phase = PrizePhase.Landfall; Say("The recovered crew can open the depot. The counterclaim will stand if they retrieve its duplicate."); return true;
        }
        CommissionWon = true; CommissionLeg = 0; Evidence += 2; Allies += 2; Prisoners++; Purse += 14;
        Strain = Math.Clamp((int)MathF.Round((1 - strength) * 44), 0, 44);
        Phase = PrizePhase.Refit; Say("The depot signs the duplicate. Its pilots agree to sail with the witness fleet."); return true;
    }
    public CampaignOrder CommissionPassage(bool raid)
    {
        string specimen = Exhibit.Item;
        return Order with
        {
            Id = Order.Id + "-bond",
            Title = raid ? "Break the bonded convoy" : "The counterclaim lighter",
            Brief = $"The receiver has transferred part of the claim to a bonded tender. Its cargo declaration lists {specimen}.",
            Objective = raid ? "Intercept the receiver’s watchers, open the tow chains, and capture their convoy."
                : "Bring a receiver’s pilot through the hidden salvage berths and lift the counterclaim from the hold.",
            Duty = raid ? SeaDuty.Blockade : SeaDuty.Salvage,
            Legs = string.IsNullOrEmpty(Order.Island) ? 8 : 6,
            SeaStations = raid ? [SeaJob.Track, SeaJob.Cut, SeaJob.DriveOff, SeaJob.Relay, SeaJob.Tow, SeaJob.Unload]
                : [SeaJob.Sound, SeaJob.Salvage, SeaJob.Tow, SeaJob.Bait, SeaJob.Guide, SeaJob.Unload],
            Boss = "The Bonded Tender",
            Homecoming = "The old receiver brings over the keys and the sealed duplicate. The second copy is still in the bonded depot.",
            PrizeWatch = false,
            Migration = false,
            Postal = false,
            Pilotage = false
        };
    }
    public CampaignOrder CommissionPort(bool exposed)
    {
        var mark = Exhibit.Mark;
        LandingStep[] steps = exposed ?
            [new(LandingAction.Brace,YardSite.Crane,"The receiver’s lift","Hold the battered lift brake while the receiver goes below"),
             new(LandingAction.Cut,YardSite.West,"Three warehouse locks","Cut through the warehouse chains before the paper finds the fire"),
             new(LandingAction.Haul,YardSite.East,"Duplicate chest","Bring the carbon copies back through the upper yard"),
             new(LandingAction.Guide,YardSite.Ferry,"The counter-signatory","Lead the buyer’s bookkeeper to the public launch")] :
            [new(LandingAction.Turn,YardSite.West,"Medicine gate","Unbar the infirmary route so the other claimants can get out"),
             new(LandingAction.Guide,YardSite.East,"The junior clerk","Take the clerk through the quiet yard to the copy room"),
             new(LandingAction.Seat,YardSite.Stairs,"The second seal",$"Check the second seal for {mark}"),
             new(LandingAction.Haul,YardSite.Ferry,"Public ledger","Carry the second account onto the witness launch")];
        return Order with
        {
            Id = Order.Id + "-depot",
            Title = exposed ? "The receiver’s burning desk" : "The bonded depot",
            Duty = SeaDuty.Landing,
            Brief = "The receivers are emptying the duplicate archive while the first case is at sea.",
            Objective = $"Recover the second declaration concerning {Exhibit.Item}, and get its witness out of the bonded depot.",
            Legs = string.IsNullOrEmpty(Order.Island) ? 8 : 6,
            LandingSteps = steps,
            Boss = "The Warehouse Receiver",
            Homecoming = "Two signed copies are afloat. The buyer sends two pilot launches to stand by the cutter at the hearing.",
            PrizeWatch = false,
            Migration = false,
            Postal = false,
            Pilotage = false
        };
    }
}
