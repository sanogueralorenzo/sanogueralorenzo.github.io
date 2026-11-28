namespace BoatsNBeasts.Core;

public static partial class FarLedger
{
    static LandingStep At(LandingAction action, YardSite site, string label, string command) => new(action,site,label,command);
    static CampaignOrder Crossing(string id, SeaDuty duty, string name, string request, string objective, string keeper,
        string result, int legs, params SeaJob[] stations) =>
        Order(id,duty,name,request,objective,keeper,result,legs) with { SeaStations = stations };
    static CampaignOrder Landfall(string id, string name, string request, string guardian, string result,
        int districts, params LandingStep[] work) => Order(id,SeaDuty.Landing,name,request,work[^1].Instruction,guardian,result,districts)
        with { LandingSteps = work };
}
