namespace BoatsNBeasts.Core;

public sealed partial class LandingYard
{
    internal void LandFromBelow(int health,int maximum,int chits,int edge,int reel)
    {
        MaximumHealth=maximum;Health=Math.Clamp(health,1,maximum);Chits=chits;Edge=Math.Min(edge,5);Quickline=Math.Min(reel,4);
    }
}
public sealed partial class UnderwayRun
{
    public LandingYard? Surface {get;private set;}
    public bool AtSurfaceLift=>Extracting&&Depth%2==1&&Depth+1<Floors;
    bool paidRoute;
    public void LaunchSurface(bool exposed)
    {
        if(!AtSurfaceLift||Surface!=null||Lost||Won||!Near(Winch,1.18f))return;
        var r=LandingRegion.From(Order.Region);int sortie=Depth/2;
        string name=r.Districts[(sortie*2+(exposed?2:0))%r.Districts.Length];
        string steward=r.Castaway;
        string title=exposed?$"{name} · the bonded warehouse":$"{name} · the witness road";
        string quarry=exposed?$"{Mark(sortie+1)} Dock Bull":$"{Mark(sortie)} Lantern Runner";
        string task=exposed?$"Recover the bonded duplicate of {CaseItem} and lower it to the next shaft.":$"Bring the {steward} through the working yards to identify {CaseMark}.";
        LandingStep[] steps=exposed?[
            new(LandingAction.Cut,YardSite.West,"Bonded rack","Cut the bond cord to expose the original docket"),
            new(LandingAction.Haul,YardSite.Fallen,CaseItem,"Hook the case off the carrier before it rolls into the slip"),
            new(LandingAction.Seat,YardSite.Crane,"Duplicate weight","Knock the duplicate into the open weighing cradle"),
            new(LandingAction.Brace,YardSite.East,"Descent line","Brace the line as the captain lowers the case to the next shaft")]:[
            new(LandingAction.Brace,YardSite.West,"Witness stair","Catch the stairstay and hold the witness landing"),
            new(LandingAction.Guide,YardSite.Stairs,steward,"Bring the witness from the fallen gate to the quiet steps"),
            new(LandingAction.Turn,YardSite.East,"Mark slip","Seal the witness’s signed slip for Nell")];
        string benefit=exposed?"The seated duplicate earns two edge fittings and three powder.":"The witness brings two rations and a lamp map.";
        var order=Order with{Id=$"{Order.Id}-outcrop-{sortie}-{(exposed?"bond":"witness")}",Title=title,Brief=$"The next shaft emerges at {name}. {task} {benefit}",Objective=task,Boss=quarry,Underways=false,LandingSteps=steps,Legs=exposed?4:3,Island=Order.Island.Length>0?Order.Island:name};
        paidRoute=exposed;Surface=new(order,unchecked(Seed+Depth*127),0,Outfit);Surface.LandFromBelow(Vitality,Maximum,Chits,Edge,Reel);
    }
    public void ReturnBelow()
    {
        if(Surface is not {} shore||(!shore.Boarded&&shore.Phase!=YardPhase.Lost))return;
        silver+=shore.Silver;Chits=shore.Chits;Edge=Math.Max(Edge,shore.Edge);Reel=Math.Max(Reel,shore.Quickline);
        Vitality=shore.Health;Clock+=shore.Clock;Surface=null;
        if(Vitality==0){Say("The line crew carries the surviving cases and loose silver back to the quay.");return;}
        if(paidRoute){Edge=Math.Min(5,Edge+2);Powder+=3;Log("A bonded duplicate now travels with the evidence.");}
        else{Rations+=2;Lamps++;Log("The witness signed the slip and marked the next service map.");}
        Depth++;LoadFloor();
    }
}
