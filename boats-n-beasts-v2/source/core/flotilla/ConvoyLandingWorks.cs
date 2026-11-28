using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed partial class ConvoyLanding
{
    public Vector2 BraceSeat(MusterBoat b)=>Plan.Walkable(Station(b.Index)+new Vector2(.83f,.56f));
    public IEnumerable<(Vector2 At,string Label)> WorkMarks(MusterBoat b)
    {
        switch(b.Role)
        {
            case MusterRole.Salvage:
                if(b.Step<2){for(int i=0;i<3;i++)if((b.Flags&(1<<i))==0)yield return(Mark(b.Index,i),$"K  Recover {Region.Marks[i]} float");}
                else if(b.Step==2)yield return(Mark(b.Index,2),"J  Cut the wreck lashing");
                else if(b.Step==3)yield return(Station(b.Index),"E  Land the iron");
                else yield return(Station(b.Index),"1 Patch hull · 2 Rescue packs · 3 Sell iron");break;
            case MusterRole.Escort:
                if(b.Step==0)yield return(Mark(b.Index,1),"L  Vara braces the roof");
                else if(b.Step==1)yield return(Mark(b.Index,2),"J  Cut the trapped hatch");
                else if(b.Step==2)yield return(Mark(b.Index,0),"E  Help the family");
                else if(Foes.Count>0)foreach(var f in Foes)yield return(f.Position,"Break the ambush");
                else yield return(Officer(b.Index),"E  Board the family");break;
            case MusterRole.Fortify:
                if(b.Step==0)yield return(Mark(b.Index,0),"K  Attach breastwork line");
                else if(b.Step==1)yield return(Mark(b.Index,1),"L  Raise the frame");
                else if(b.Step==2)yield return(b.Load,"J  Drive beam toward brass shoe");
                else yield return(BraceSeat(b),"E  Peg the breastwork");break;
        }
    }
    bool DoWork(MusterBoat b,char key)
    {
        int i=b.Index;
        switch(b.Role)
        {
            case MusterRole.Salvage:
                if(key=='K'&&b.Step<2)
                {
                    int marker=Enumerable.Range(0,3).Where(n=>(b.Flags&(1<<n))==0).MinBy(n=>Vector2.DistanceSquared(Player,Mark(i,n)));
                    if(!Near(Mark(i,marker),1.87f))return false;b.Flags|=1<<marker;b.Step++;Tether(Mark(i,marker));if(b.Step==2)Say("Two marked bundles are safe. Cut the live wreck free before hauling it home.");return true;
                }
                if(key=='J'&&b.Step==2&&Near(Mark(i,2),1.18f)){b.Step++;b.Load=Mark(i,2);Spawn(YardBeast.Scrapper,Mark(i,0));Say("The wreck breaks free. Bring the iron to the flag and keep its claimant off the crew.");return true;}
                if(key=='E'&&b.Step==3&&Near(Station(i),1.18f)&&Vector2.Distance(b.Load,Station(i))<2&&Foes.Count==0){b.Step++;Say("Use the iron. Patch this boat, pack two field rations or sell it and keep the spare gun carriages.");return true;}
                return false;
            case MusterRole.Escort:
                if(key=='L'&&b.Step==0&&Near(Mark(i,1),1.24f)){b.Step++;Flash=.32f;return true;}
                if(key=='J'&&b.Step==1&&Near(Mark(i,2),1.17f)){b.Step++;return true;}
                if(key=='E'&&b.Step==2&&Near(Mark(i,0),1.18f)){b.Step++;b.Passenger=Mark(i,0);Spawn(YardBeast.Scrapper,Mark(i,1));Spawn(YardBeast.Slinger,Mark(i,2));Say("The family takes your rope. Lead them back to the low dock.");return true;}
                if(key=='E'&&b.Step==3&&Foes.Count==0&&Near(Officer(i),1.19f)&&Vector2.Distance(b.Passenger,Officer(i))<2.05f){b.People+=2;Health=Math.Min(Maximum,Health+2);Finish(b);return true;}return false;
            case MusterRole.Fortify:
                if(key=='K'&&b.Step==0&&Near(Mark(i,0),1.57f)){b.Step++;Tether(Mark(i,0));return true;}
                if(key=='L'&&b.Step==1&&Near(Mark(i,1),1.22f)){b.Step++;b.Load=Station(i)-new Vector2(.56f,.36f);Flash=.38f;return true;}
                if(key=='J'&&b.Step==2&&Near(b.Load,1.15f))
                {
                    var d=b.Load-Player;if(d.LengthSquared()<.014f)d=Heading;b.Load=Plan.Patches[i==0?1:i==1?2:4].Closest(b.Load+Unit(d)*.38f);
                    if(Vector2.Distance(b.Load,BraceSeat(b))<.49f){b.Load=BraceSeat(b);b.Step++;}return true;
                }
                if(key=='E'&&b.Step==3&&Near(BraceSeat(b),1.15f)){b.Timbers+=2;Finish(b);return true;}return false;
        }
        return false;
    }
    void Tether(Vector2 pos){LineEnd=pos;EventTime=.42f;HookWait=.65f;}
    public void Tick(float dt,Vector2 move,bool cut,bool dodge)
    {
        if(Lost||Won)return;Clock+=dt;LineTime=Cool(LineTime,dt);Flash=Cool(Flash,dt);Swing=Cool(Swing,dt);EventTime=Cool(EventTime,dt);HookWait=Cool(HookWait,dt);DodgeWait=Cool(DodgeWait,dt);Hurt=Cool(Hurt,dt);cutWait=Cool(cutWait,dt);signalWait=Cool(signalWait,dt);safe=Cool(safe,dt);Dashing=Cool(Dashing,dt);
        if(move.LengthSquared()>1)move=Unit(move);if(move.LengthSquared()>.02f)Heading=move;
        if(dodge&&DodgeWait==0){Dashing=.18f;DodgeWait=1.17f;dashHeading=Unit(Heading);safe=.29f;}
        Player=Plan.Walkable(Player+(Dashing>0?dashHeading*11.2f:move*4.35f)*dt);
        Mate=Follow(Mate,Player-Heading*.64f+new Vector2(.36f,.14f),dt*5.1f);
        Gunner=Follow(Gunner,Player-Heading*.76f-new Vector2(.48f,.15f),dt*5.0f);
        foreach(var b in Boats.Where(b=>b.Hull>0))
        {
            var dst=b.Role==MusterRole.Unposted?Officer(b.Index):b.LeftDock>=0?Launch(b.Index):Station(b.Index);
            b.Worker=Follow(b.Worker,dst,dt*3.17f);
        }
        if(Phase==MusterPhase.Consign&&FreightStep==2)Freight=Follow(Freight,Player,dt*3.85f);
        if(Team is { } team)
        {
            if(team.Role==MusterRole.Escort&&team.Step==3)team.Passenger=Follow(team.Passenger,Near(Officer(team.Index),1.18f)?Officer(team.Index):Player,dt*3.75f);
            if(team.Role==MusterRole.Salvage&&team.Step==3)team.Load=Follow(team.Load,Player,dt*3.99f);
        }
        if(cut&&cutWait==0&&Dashing==0){cutWait=.36f;Swing=.21f;if(!FreeLine('J')&&(Team==null||!DoWork(Team,'J')))Cut();}
        Battle(dt);
        for(int i=Drops.Count-1;i>=0;i--)if(Near(Drops[i],1.1f)){Silver++;Drops.RemoveAt(i);}
    }
    Vector2 Follow(Vector2 at,Vector2 target,float step)
    {
        if(Vector2.DistanceSquared(at,target)<.015f)return target;
        var head=Plan.CanWalk(at,target)?target:Plan.Waypoint(at,target);var d=head-at;
        return d.Length()<=step?head:Plan.Walkable(at+Unit(d)*step);
    }
    public void Hook()
    {
        if(Lost||Won||HookWait>0)return;
        if(FreightAction('K')||FreeLine('K'))return;
        if(Team is {} b&&DoWork(b,'K'))return;
        if(Phase==MusterPhase.Tideway&&ChannelBoard is {} chart)
        {
            var post=Boats.Where(b=>b.Hull>0&&!chart.Home(b.Index)).MinBy(b=>Vector2.DistanceSquared(Player,GatePost(b.Index)));
            if(post!=null&&Near(GatePost(post.Index),1.05f)){if(chart.Dredge(post.Index,post)){Tether(GatePost(post.Index));Say("Lio spends one salvaged fitting to open that bar.");}else Say("Aim the boat at a bar and bring one salvaged fitting to dredge it.");}return;
        }
        if(Phase==MusterPhase.Locks&&Near(GatePost(0),1.65f)){LockPins|=1;Tether(GatePost(0));return;}
        var f=Foes.MinBy(f=>Vector2.DistanceSquared(f.Position,Player));if(f==null||!Near(f.Position,Outfit==Loadout.Longline?5.25f:4.15f))return;
        bool counter=Attacks.RemoveAll(a=>a.Source==f&&!a.Fired)>0;Tether(f.Position);HookWait=Outfit==Loadout.Longline?2.80f:3.79f;
        if(f.Kind!=YardBeast.Guardian||HeldLines==0)f.Health-=counter?13:3;f.Stagger=counter?1.35f:.43f;f.Hit=.17f;
        if(f.Kind!=YardBeast.Guardian)f.Position=Plan.Walkable(Vector2.Lerp(f.Position,Player,.27f));
    }
    public void Signal()
    {
        if(Lost||Won)return;if(FreightAction('L')||FreeLine('L'))return;if(Team is {} b&&DoWork(b,'L'))return;
        if(Phase==MusterPhase.Tideway&&ChannelBoard is {} chart)
        {
            if(Near(Plan.Gate,1.17f))
            {
                var result=chart.Sound(Boats,Clock);Silver+=result.Silver;Flash=.3f;Say(result.Report);
                if(Alive==0)Phase=MusterPhase.Lost;
                else if(Boats.All(b=>b.Hull<=0||chart.Home(b.Index))){Phase=MusterPhase.Embark;Say("The last hull is past the shoals. Take the release lines off their posts.");}
            }
            return;
        }
        if(Phase==MusterPhase.Locks&&Near(GatePost(2),1.42f)){LockPins|=2;Flash=.38f;return;}
        if(signalWait>0)return;var f=Foes.Where(f=>Near(f.Position,6f)).MinBy(f=>f.Health);if(f==null)return;
        LineEnd=f.Position;Flash=.44f;int stores=Boats.Sum(b=>b.Hull>0?b.Stores:0);if(f.Kind!=YardBeast.Guardian||HeldLines==0)f.Health-=5+Math.Min(8,stores);f.Stagger=.48f;signalWait=Math.Max(1.90f,4.6f-stores*.42f);
    }
    public bool CallShipmate(Shipmate s)
    {
        if(Lost||Won)return false;
        if(s==Shipmate.Vara&&Health<Maximum){Health=Math.Min(Maximum,Health+4);return true;}
        if(s==Shipmate.Nell){safe=Math.Max(4,safe);Attacks.Clear();return true;}
        if(s==Shipmate.Lio&&Foes.Any(f=>Near(f.Position,6))){foreach(var f in Foes.Where(f=>Near(f.Position,6))){f.Stagger=2.6f;Attacks.RemoveAll(a=>a.Source==f);}return true;}
        return false;
    }
}
