namespace BoatsNBeasts.Core;

public enum LandingAction { Turn, Cut, Haul, Brace, Seat, Guide }
public enum YardSite { Fallen, West, East, Crane, Stairs, Ferry }
public sealed record LandingStep(LandingAction Action,YardSite Site,string Label,string Instruction);

internal static class LandingContract
{
    static LandingStep Turn(YardSite site,string label,string action)=>new(LandingAction.Turn,site,label,action);
    static LandingStep Cut(YardSite site,string label,string action)=>new(LandingAction.Cut,site,label,action);
    static LandingStep Haul(YardSite site,string label,string action)=>new(LandingAction.Haul,site,label,action);
    static LandingStep Brace(YardSite site,string label,string action)=>new(LandingAction.Brace,site,label,action);
    static LandingStep Seat(YardSite site,string label,string action)=>new(LandingAction.Seat,site,label,action);
    static LandingStep Guide(YardSite site,string label,string action)=>new(LandingAction.Guide,site,label,action);

    public static LandingStep[] For(CampaignOrder o)=>o.LandingSteps is { Length: > 0 } authored ? authored : o.Id switch
    {
        "cinder-kiln"=>[Turn(YardSite.Fallen,"Yoke keys","Lift the kiln keys from the Ox’s yoke"),Turn(YardSite.West,"Cool slip","Unlock the crews on the cool slip"),Turn(YardSite.East,"Firing drum","Unlock the three clay ferries")],
        "cinder-ashroom"=>[Cut(YardSite.West,"Boarded ashroom","Cut the tariff boards off the ashroom"),Haul(YardSite.Crane,"Turned tiles","Pull the face-in tiles down with Lio"),Turn(YardSite.East,"Tiled register","Wrap the signed register in sailcloth")],
        "reed-rag"=>[Cut(YardSite.West,"Rag-yard gate","Break the rag pickers out of the mill"),Turn(YardSite.East,"Dry sheet","Take the last dry sheet from the frame"),Guide(YardSite.Stairs,"Pell’s skiff","Escort the rag picker out with the dry sheet")],
        "reed-lock"=>[Haul(YardSite.Fallen,"Brass thimble","Hook Oren’s thimble out of the ratchet"),Brace(YardSite.West,"Sluice pawl","Hold the pawl while the captain releases the sluice"),Turn(YardSite.East,"Channel gate","Turn the channel toward the old street")],
        "pear-nursery"=>[Haul(YardSite.West,"Port lift handle","Hook the port lift through the cocoon"),Brace(YardSite.East,"Nursery lift","Hold the nursery level while Ilo slips the latch"),Turn(YardSite.Stairs,"Wicker cradle","Lower the nursery onto the landing")],
        "pear-cradle"=>[Cut(YardSite.West,"Packing loft","Cut the planks off the abandoned loft"),Haul(YardSite.East,"False floor","Lift the second floor with the crew line"),Turn(YardSite.Crane,"Pip’s list","Copy the names beneath the floor")],
        "ice-lung"=>[Haul(YardSite.Fallen,"Boiler strap","Unhook the walrus’s boiler straps"),Seat(YardSite.West,"Valve saddle","Knock the loose stop into the valve saddle"),Turn(YardSite.East,"Hot main","Bleed the hot main into the infirmary")],
        "ice-cook"=>[Cut(YardSite.West,"Cold pantry","Open the frozen pantry door"),Turn(YardSite.East,"Recipe wall","Take a rubbing of Jo’s supper list"),Turn(YardSite.Stairs,"Frost paper","Seal the rubbing under waxed cloth")],
        "loom-overcast"=>[Brace(YardSite.West,"Master shuttle","Hold the warp while Jo frees the master shuttle"),Cut(YardSite.East,"Platform ties","Cut the released platform ties"),Guide(YardSite.Stairs,"Lower platform","Bring the last weaver down to the landing")],
        "loom-figure"=>[Haul(YardSite.Fallen,"Turning gear","Take the turning gear off Tally Jack"),Seat(YardSite.West,"Wage press","Seat the turning gear in the wage press"),Turn(YardSite.East,"Wage chest","Open the chest for the unpaid shift")],
        "choir-lung"=>[Haul(YardSite.East,"Blocked air pipe","Pull the coral obstruction out of the air pipe"),Brace(YardSite.West,"Oxygen bell","Hold the bronze bell clear of the dispensary"),Guide(YardSite.Stairs,"Open air","Help Oren carry the oxygen bell outside")],
        "choir-bed"=>[Haul(YardSite.Fallen,"Pocket watch","Recover the watch from the lamprey"),Cut(YardSite.East,"Payroll lockers","Break the seal on the payroll lockers"),Turn(YardSite.West,"Examiner’s warrant","Take the examiner’s warrant from the file")],
        "sable-dog"=>[Turn(YardSite.Fallen,"Detention keys","Lift the detention keys from the hound"),Turn(YardSite.West,"Bottom bench","Unlock the holding bench"),Guide(YardSite.Stairs,"Public steps","Lead the waiting pilots out to the quay")],
        "sable-ballast"=>[Turn(YardSite.West,"Weight room","Open the court’s weight room"),Haul(YardSite.East,"Master weight","Lift the hollow master weight onto the bench"),Turn(YardSite.Crane,"Little compass","Carry the little compass into the hearing")],
        "north-axle"=>[Brace(YardSite.West,"West counterweight","Hold the lamp rail and release its counterweight"),Haul(YardSite.East,"Second counterweight","Hook the second counterweight clear"),Turn(YardSite.Crane,"Engine floor","Open the engine floor for the harbor crews")],
        "north-hart"=>[Haul(YardSite.Fallen,"Survey harness","Hook the survey platform off the antlers"),Cut(YardSite.West,"Platform stays","Cut the platform stays from the island"),Guide(YardSite.Stairs,"Still shore","Bring Gauge off as the walking island stops")],
        _=>[Turn(YardSite.Fallen,"Manifest",o.Objective)]
    };
}
