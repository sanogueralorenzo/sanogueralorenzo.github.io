using System.Numerics;

namespace BoatsNBeasts.Core;

public sealed partial class FleetCommand
{
    public FleetPilot? Pilot { get; private set; }
    public FleetRole? NextPilot => Field switch
    {
        FleetField.Rescue when Rescued >= 3 => FleetRole.Tender,
        FleetField.Passage when Delivered >= 2 => FleetRole.Tug,
        FleetField.Captain when Surrendered => FleetRole.Sloop,
        _ => null
    };
    CommandHull? pilotHull;
    int reported;
    CommandHull Watchkeeper(FleetRole role) => Allies.FirstOrDefault(a => a.Role == role && a.Afloat) ?? Allies.First(a => a.Afloat);
    bool BoardPilot(FleetRole role)
    {
        if (HullsAfloat == 0) return false;
        var keeper = Watchkeeper(role);
        if (Vector2.DistanceSquared(keeper.Position, Ship.Position) > 210 * 210) return false;
        pilotHull = keeper; reported = 0;
        Pilot = new(role, keeper, Order.Articles, variant + Order.Tier + fieldNo, HullsAfloat);
        Say(keeper.Skipper + " makes room at the helm. The rest of the flotilla will cover the working boat."); return true;
    }
    void CreditPilot() { Silver += Pilot!.Silver - reported; reported = Pilot.Silver; }
    void WatchPilot(float dt, SailInput input)
    {
        var pilot = Pilot!;
        pilot.Tick(dt, input);
        CreditPilot();
        pilotHull!.Hull = Math.Max(0, pilot.Integrity);
        if (pilot.Lost)
        {
            Field = FleetField.Lost; Pilot = null; Say("The launch takes water under the battery. The flotilla recovers its surviving hands and the coin already aboard."); return;
        }
        if (!pilot.Won) return;
        var role = pilot.Role; Pilot = null; pilotHull = null;
        if (role == FleetRole.Tender) { Rescued += pilot.Saved; CloseField(Order.Legs >= 3 ? FleetField.Passage : FleetField.Captain); }
        else if (role == FleetRole.Tug) CloseField(FleetField.Captain);
        else CloseField(FleetField.Refuge);
    }
}
