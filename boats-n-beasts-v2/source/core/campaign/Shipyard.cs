namespace BoatsNBeasts.Core;

public enum Loadout { Standard, Longline, Broadside, Lifeboat }
public sealed record OutfitterPlan(Loadout Kit, string Name, int Silver, string Description);

public static class Shipyard
{
    public static readonly OutfitterPlan[] Plans = [
        new(Loadout.Standard,"Quay rig",0,"Balanced gear for Lio and Vara."),
        new(Loadout.Longline,"Line crew",38,"At sea the line reaches 175 farther and recovers one second sooner. Ashore it gains 1.3 m and recovers one second sooner, while each cut loses one damage."),
        new(Loadout.Broadside,"Gun crew",54,"Broadsides gain 50% damage. Bow and stern shots lose 25%. Ashore each cut adds three damage, and the dodge takes half a second longer to recover."),
        new(Loadout.Lifeboat,"Rescue crew",64,"Carry two extra kits. Each repairs 55 hull and 35 per lighter. Refit for kits in place of artillery. Ashore gain four vitality and faster escorts, with one second longer between hooks.")
    ];
    public static HarborLedger Equip(this HarborLedger ledger, OutfitterPlan plan)
    {
        if (!ledger.Dedicated || !Plans.Contains(plan)) return ledger;
        if (plan.Kit == Loadout.Standard || ledger.Patterns.Contains(plan.Kit))
            return ledger with { Outfit = plan.Kit };
        if (ledger.Silver < plan.Silver) return ledger;
        return ledger with { Outfit = plan.Kit, Patterns = [..ledger.Patterns,plan.Kit], Silver = ledger.Silver-plan.Silver };
    }
}
