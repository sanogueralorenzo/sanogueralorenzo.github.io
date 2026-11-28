using System.Numerics;

namespace BoatsNBeasts.Core;

public enum LandingJob { Weights, Nets, Mould, Escort, Capstans, Breakers }
public enum YardPhase { Fork, BranchFight, Work, Crossroads, GateFight, Camp, Guardian, Keys, Release, Departure, Lost }
public enum YardBeast { Scrapper, Slinger, Porter, Skater, Guardian }
public enum AttackShape { Disc, Ring, Lane, Fan }

public sealed class YardBeastState(Vector2 position, YardBeast kind, int health)
{
    public Vector2 Position = position, Heading = -Vector2.UnitY, RushTo;
    public readonly YardBeast Kind = kind;
    public readonly int Maximum = health;
    public int Health = health, Pattern;
    public float Wait = .9f, Stagger, Hit, Rush;
    public bool Enraged;
}

public sealed class YardAttack(YardBeastState source, AttackShape shape, Vector2 origin, Vector2 target, float radius,
    float inner, float lead, float active, bool rush = false)
{
    public readonly YardBeastState Source = source;
    public readonly AttackShape Shape = shape;
    public readonly Vector2 Origin = origin, Target = target;
    public readonly float Radius = radius, Inner = inner, Lead = lead, Active = active;
    public readonly bool Rush = rush;
    public float Age;
    public bool Fired, Hurt;
    public float Windup => Math.Clamp(Age / Lead, 0, 1);
    public bool Contains(Vector2 p)
    {
        float range = Vector2.Distance(p, Origin);
        return Shape switch
        {
            AttackShape.Ring => range >= Inner && range <= Radius,
            AttackShape.Disc => range <= Radius,
            AttackShape.Lane => SegmentDistance(p,Origin,Target)<=Radius,
            _ => range<=Radius && (range<.18f || Vector2.Dot((p-Origin)/range,Vector2.Normalize(Target-Origin))>=Inner)
        };
    }
    static float SegmentDistance(Vector2 p, Vector2 a, Vector2 b)
    {
        var axis=b-a;
        float fraction=Math.Clamp(Vector2.Dot(p-a,axis)/Math.Max(.001f,axis.LengthSquared()),0,1);
        return Vector2.Distance(p,a+axis*fraction);
    }
}

public sealed class LandingYard
{
    public static readonly Vector2 Camp = QuayPaths.Summit + new Vector2(-2.8f,-.3f);
    public static readonly Vector2 Gate = QuayPaths.Belfry;
    public static readonly Vector2[] Locks = [QuayPaths.Summit + new Vector2(-2.7f,.75f),QuayPaths.Summit + new Vector2(2.7f,.75f)];
    public static readonly Vector2 Ferry = QuayPaths.Summit + new Vector2(2.55f,-1.55f);
    public readonly CampaignOrder Order;
    public readonly LandingRegion Region;
    public readonly Loadout Outfit;
    public readonly List<YardBeastState> Foes = [];
    public readonly List<YardAttack> Attacks = [];
    public readonly List<Vector2> SilverDrops = [];
    public readonly bool[] Completed = new bool[2];
    public readonly LandingJob[] Options = new LandingJob[2];
    public readonly int[] Sequence=[0,1,2];
    public readonly bool[] Secured=new bool[3];
    public Vector2 Player = QuayPaths.Dock, Mate = QuayPaths.Dock+new Vector2(.25f,-.6f), Heading=-Vector2.UnitY;
    public Vector2 HookEnd, Billet, Passenger, KeyPlace;
    public YardPhase Phase {get;private set;}=YardPhase.Fork;
    Vector2 westOffset,eastOffset,summitOffset;
    public Vector2 World(Vector2 point)
    {
        float first=Math.Clamp((-point.Y-3.55f)/2.13f,0,1),upper=Math.Clamp((-point.Y-10.45f)/3.18f,0,1);
        float side=Math.Clamp((point.X+2.12f)/4.24f,0,1);
        return point+Vector2.Lerp(westOffset,eastOffset,side)*first*(1-upper)+summitOffset*upper;
    }
    public Vector2 WalkingIntent(Vector2 point,Vector2 physical)
    {
        if(physical.LengthSquared()<.00001f)return Vector2.Zero;
        var dx=(World(point+Vector2.UnitX*.012f)-World(point))/.012f;
        var dz=(World(point+Vector2.UnitY*.012f)-World(point))/.012f;
        float det=dx.X*dz.Y-dx.Y*dz.X;
        return MathF.Abs(det)>.03f ? new((physical.X*dz.Y-physical.Y*dz.X)/det,(dx.X*physical.Y-dx.Y*physical.X)/det) : physical;
    }
    public int BrokenBridge {get;private set;} = -1;
    public int District {get;private set;}
    public int Branch {get;private set;}=-1;
    public int Health {get;private set;}
    public int MaximumHealth {get;private set;}
    public int Silver {get;private set;}
    public int Chits {get;private set;}
    public int Edge {get;private set;}
    public int Quickline {get;private set;}
    public int Progress {get;private set;}
    public bool Carrying {get;private set;}
    public bool Anchored {get;private set;}
    public bool Intercept {get;private set;}
    public Vector2 Delivery => QuayPaths.Summit+new Vector2(Branch==0?-2.4f:2.4f,1.60f);
    public Vector2 ScaleSite => Workbench+new Vector2(Branch==0?1.3f:-1.3f,-.70f);
    public bool Repaired {get;private set;}
    public Vector2 RepairPost
    {
        get
        {
            if(BrokenBridge<0)return Vector2.Zero;
            var (a,b)=QuayPaths.Bridges[BrokenBridge];var left=Vector2.Lerp(a,b,.34f);var right=Vector2.Lerp(a,b,.66f);
            return Vector2.DistanceSquared(Player,left)<Vector2.DistanceSquared(Player,right)?left:right;
        }
    }
    public int GuardCount {get;private set;}
    readonly LandingStep[] contract;
    public int FinalIndex {get;private set;}
    public LandingStep FinalStep => contract[Math.Min(FinalIndex,contract.Length-1)];
    public bool Braced {get;private set;}
    public readonly bool[] GuardPins = new bool[2], HotPins = new bool[2];
    public bool Harness => GuardPins.Any(x=>x);
    public bool ChargeHarness=>Order.Id=="cinder-kiln"||Order.Id=="sable-dog";
    public string GuardFitting => Region.Climate switch {
        IslandClimate.Kiln=>"yoke pin",IslandClimate.Orchard=>"wing stay",IslandClimate.Delta=>"press peg",IslandClimate.Shelf=>"steam vent",
        IslandClimate.Loom=>"warp spool",IslandClimate.Reef=>"air valve",IslandClimate.Court=>"bench pin",_=>"survey wire"};
    public bool Finishing => Phase is YardPhase.Keys or YardPhase.Release;
    public Vector2 FinalSite=>FinalStep.Site switch {
        YardSite.West=>Locks[0],YardSite.East=>Locks[1],YardSite.Fallen=>KeyPlace,YardSite.Crane=>Gate,
        YardSite.Stairs=>QuayPaths.Summit+new Vector2(0,2.3f),_=>Ferry};
    public Vector2 ReleaseLever=>FinalSite+new Vector2(FinalSite.X>0?-1.6f:1.6f,.75f);
    public Vector2 DeliverTo=>QuayPaths.Summit+new Vector2(.65f,2.25f);
    public float Clock, Swing, Hook, Dash, Hurt, HookWait, DodgeWait, LineClock;
    public string Line = "";
    public bool Boarded {get;private set;}
    public bool PassengerFree {get;private set;}
    public bool AtCamp => Vector2.Distance(Player,Camp)<1.45f;
    public bool CanTrade => Phase == YardPhase.Camp && AtCamp;
    public int LegCount => Math.Max(1,Order.Legs);
    public LandingJob Job => Options[Math.Max(0,Branch)];
    public Vector2 Workbench => QuayPaths.Bells[Math.Max(0,Branch)];
    public Vector2 Mould => Workbench+new Vector2(1.03f,.85f);
    public string DistrictName => Region.Districts[District%Region.Districts.Length];
    public string Objective => Phase switch
    {
        YardPhase.Fork => "Choose a yard to enter",
        YardPhase.BranchFight => "Clear the work yard",
        YardPhase.Work => Job switch {
            LandingJob.Weights => Carrying ? "Weigh the stamp at the register" : $"Find {Region.Marks[Sequence[Math.Min(2,Progress)]]}  ·  {Progress}/3",
            LandingJob.Nets => Carrying ? "Carry the net to the upper crane" : $"Snag the drift lines  ·  {Progress}/3",
            LandingJob.Mould => Carrying ? "Deliver the cast piece to the upper slip" : $"Drive the {Region.Pin} into its seat",
            LandingJob.Escort => PassengerFree?"Lead the worker to the marked steps":$"Free the {Region.Castaway}",
            LandingJob.Capstans => Anchored ? $"Turn the {Region.Marks[Sequence[Math.Min(2,Progress)]]} winch" : "Catch the central cable with Lio’s hook",
            _ => $"Break the guard seals  ·  {Progress}/3" },
        YardPhase.Crossroads=>"Take the upper gate or work the other yard",
        YardPhase.GateFight=>"Open the toll gate",
        YardPhase.Camp=>District+1<LegCount?"Trade or take the north ferry":"Trade or open the last gate",
        YardPhase.Guardian=>Harness ? (ChargeHarness?"Lure a charge through each gold pin":"Unfasten the two marked "+GuardFitting+"s") : $"Break {Order.Boss}’s guard",
        YardPhase.Keys or YardPhase.Release=>FinalStep.Instruction,
        YardPhase.Departure=>"Board with your crew",
        _=>"The crew rows for home"
    };
    readonly int seed;
    Random rand=null!;
    Vector2 dashDirection, billetVelocity, lastTrail;
    readonly Queue<Vector2> trail=[];
    float swingDelay, safe;
    bool fed;
    public LandingYard(CampaignOrder order,int seed,int stores,Loadout outfit=Loadout.Standard)
    {
        Order=order;Outfit=outfit;Region=LandingRegion.From(order.Region);contract=LandingContract.For(order);this.seed=seed;
        MaximumHealth=Health=8+Math.Clamp(stores,0,2)*2+(Outfit==Loadout.Lifeboat?4:0);GenerateDistrict();
    }
    void GenerateDistrict()
    {
        uint orderKey=2166136261;
        foreach(char letter in Order.Id)orderKey=unchecked((orderKey^letter)*16777619);
        rand=new(unchecked((int)SeedRandom.Hash((uint)seed,District,Order.Tier,orderKey)));
        var start=(int)Region.Climate+District*2+(int)(orderKey%6);
        Options[0]=(LandingJob)((start+rand.Next(2))%6);
        Options[1]=(LandingJob)(((int)Options[0]+1+rand.Next(4))%6);
        rand.Shuffle(Sequence);
        westOffset=new(-.25f-rand.NextSingle()*1.35f,-.16f-rand.NextSingle()*1.37f);
        eastOffset=new(.15f+rand.NextSingle()*1.62f,-rand.NextSingle()*1.13f);
        summitOffset=new((rand.NextSingle()-.5f)*3.05f,Math.Min(westOffset.Y,eastOffset.Y)-rand.NextSingle()*1.55f);
        BrokenBridge=District==0?-1:rand.Next(5);Repaired=false;
        Player=QuayPaths.Dock;Mate=Player+new Vector2(.25f,-.5f);
        Branch=-1;Phase=YardPhase.Fork;fed=false;
        Array.Clear(Completed); Foes.Clear();Attacks.Clear();SilverDrops.Clear();ClearJob();
        Say(District==0?Order.Brief:"Vara opens the route book at "+DistrictName+". The ferryman will take fresh work chits.");
    }
    public string JobTitle(LandingJob job) => job switch
    {
        LandingJob.Weights=>"Seal room",LandingJob.Nets=>"Drift berth",LandingJob.Mould=>"Pin foundry",
        LandingJob.Escort=>"Workers’ lock",LandingJob.Capstans=>"Winch house",_=>"Toll inspection"
    };
    public Vector2 Mark(int index)
    {
        Vector2[] local=[new(-1.40f,-.63f),new(.07f,1.46f),new(1.36f,-.53f)];
        if(Job==LandingJob.Weights||Job==LandingJob.Breakers)
        {
            if(index==0)return Workbench+local[0];
            if(index==1)return new Vector2(Branch==0?-2.1f:2.1f,-1.35f);
            return QuayPaths.Bells[1-Branch]+local[2];
        }
        return Workbench+local[index];
    }
    public Vector2 Float(int index)
    {
        float angle= (index==0?-.5f:index==1?1.42f:3.28f)+MathF.Sin(Clock*.68f+index)*.22f;
        return Workbench+new Vector2(2.85f*MathF.Cos(angle),2.58f*MathF.Sin(angle));
    }
    void Say(string line){Line=line;LineClock=6;}
    void ClearJob()
    {
        Progress=0;PassengerFree=Carrying=Anchored=Intercept=false;trail.Clear();Array.Clear(Secured);billetVelocity=Vector2.Zero;
    }
    void Pick(int side)
    {
        Branch=side;ClearJob();Phase=YardPhase.BranchFight;
        SpawnWatch(Workbench,false);
        Say(side==0?"Lio takes the outer line. Cut across their swing when the painted ground clears.":"Vara climbs onto the rail. She points out the gaps in the toll guard.");
    }
    void SpawnWatch(Vector2 center,bool gate)
    {
        int count=gate?2+Math.Min(District/2,2):2+Math.Min(District%3,1);
        if(Order.Tier>=5&&District>0)count++;
        GuardCount=count;
        for(int i=0;i<count;i++)
        {
            float a=(i+.3f)*MathF.Tau/count;
            var local=new Vector2(MathF.Cos(a)*(gate?2.8f:1.78f),MathF.Sin(a)*(gate?1.9f:1.25f));
            var kind=(YardBeast)((rand.Next(4)+(int)Region.Climate+i)%4);
            int hp=kind==YardBeast.Porter?34:kind==YardBeast.Slinger?20:25;
            Foes.Add(new(Walkable(center+local),kind,hp){Wait=.8f+i*.24f});
        }
    }
    public void Interact()
    {
        int side=Array.FindIndex(QuayPaths.Bells,p=>Vector2.Distance(Player,p)<1.30f);
        if (Phase is YardPhase.Fork or YardPhase.Crossroads && side>=0 && !Completed[side]){Pick(side);return;}
        if(Phase==YardPhase.Crossroads && Near(Gate,1.55f))
        {
            Phase=YardPhase.GateFight;SpawnWatch(QuayPaths.Summit,true);
            Say("The watch has the release lever. Clear the head of the slip.");return;
        }
        if(Phase==YardPhase.Camp && Near(Gate,1.55f))
        {
            if(District+1<LegCount){District++;GenerateDistrict();return;}
            Phase=YardPhase.Guardian;Branch=-1;
            int hp=122+Math.Min(3,Order.Tier/2)*11;
            Foes.Add(new(QuayPaths.Summit+new Vector2(0,-.40f),YardBeast.Guardian,hp){Wait=1.4f});
            Say(Order.Boss+" blocks the upper yard. Hook at the wind-up. Strike when the guard drops.");return;
        }
        if(Finishing)
        {
            if(FinalStep.Action==LandingAction.Turn&&Near(FinalSite,1.24f))AdvanceFinal();
            else if(FinalStep.Action==LandingAction.Brace&&Braced&&Near(ReleaseLever,1.14f))AdvanceFinal();
            else if(FinalStep.Action==LandingAction.Guide&&!PassengerFree&&Near(Passenger,1.18f))
            {PassengerFree=true;lastTrail=Player;trail.Enqueue(Player);Say("Stay together. Lead them out to the marked steps.");}
            return;
        }
        if(Phase==YardPhase.Departure&&Near(Ferry,1.55f)){Boarded=true;return;}
        if(Phase!=YardPhase.Work)return;
        if(Carrying)
        {
            var delivery=Job==LandingJob.Weights?ScaleSite:Delivery;
            if(!Near(delivery,1.25f)){Say("The marked receiver is waiting for the load.");return;}
            Carrying=false;
            if(Job==LandingJob.Weights){Secured[Sequence[Progress]]=true;JobStep();}
            else CompleteJob();
            return;
        }
        if(Job is LandingJob.Weights or LandingJob.Capstans)
        {
            for(int i=0;i<3;i++)
                if(Near(Mark(i),.94f))
                {
                    if(i==Sequence[Progress]&&Job==LandingJob.Weights){Carrying=true;Say("That's the stamped load. Carry it to the brass scale at the register.");}
                    else if(i==Sequence[Progress]&&Anchored){Anchored=false;Secured[i]=true;JobStep();}
                    else if(i==Sequence[Progress])Say("Lio must catch the cable with K before you turn the winch.");
                    else Say("The mark in the register is "+Region.Marks[Sequence[Progress]]+".");
                    return;
                }
        }
        else if(Job==LandingJob.Escort&&!PassengerFree&&Near(Passenger,1.18f))
        {
            PassengerFree=true;lastTrail=Player;trail.Enqueue(Player);
            Say("Stay close. The painted steps overlook the freight lock.");
        }
        else if(Job==LandingJob.Mould&&!Carrying&&Near(Workbench,1.1f))
        {Billet=Workbench+new Vector2(-.9f,-.40f);billetVelocity=Vector2.Zero;Say("Pin back on the block. Knock it toward the striped seat.");}
    }
    bool Near(Vector2 p,float range)=>Vector2.DistanceSquared(Player,p)<range*range;
    void BeginJob()
    {
        Phase=YardPhase.Work;ClearJob();
        Billet=Workbench+new Vector2(-.9f,-.4f); Passenger=Mark(Branch==0?2:0);
        Say(Job switch
        {
            LandingJob.Weights=>"Read the three seals on the register. Press E at each matching clay tablet.",
            LandingJob.Nets=>"The tide has carried three corked lines out. Follow the rim and call Lio’s hook with K.",
            LandingJob.Mould=>$"Position behind the {Region.Pin}. J knocks it into the striped seat. K draws it back.",
            LandingJob.Escort=>$"One {Region.Castaway} is stranded on the slip. Help them up with E and lead them to the lower wharf.",
            LandingJob.Capstans=>"Crank the marked winches with E. Mind the travelling counterweights on the track.",
            _=>"Three guard seals. Cut the two cargo lids with J and lift the iron lid at the lower landing with K."
        });
    }
    void JobStep()
    {
        if(++Progress>=3)
        {
            if(Job==LandingJob.Nets){Carrying=true;Say("The net has all three floats. Carry the catch to the marked crane in the upper slip.");}
            else CompleteJob();
        }
        else Say(Job==LandingJob.Weights||Job==LandingJob.Capstans?"Next mark  ·  "+Region.Marks[Sequence[Progress]]:"Line clear. Keep moving.");
    }
    void CompleteJob()
    {
        Completed[Branch]=true;Phase=YardPhase.Crossroads;
        Chits+=Branch==0?2:3;Silver+=2;
        Say(Completed.All(x=>x)?"Both yards are open. Take either high walk to the freight gate.":"You have the freight stamp. Work the other yard for extra chits, or head to the upper gate.");
    }
    public void Trade(int slot)
    {
        if(!CanTrade)return;
        int cost=slot==1?1:slot==4?4:2;
        if(Chits<cost){Say($"The trader asks {cost} work chits.");return;}
        switch(slot)
        {
            case 1:
                if(fed||Health==MaximumHealth){Say("The ration tin is full.");return;}
                fed=true;Health=Math.Min(MaximumHealth,Health+5);break;
            case 2:
                if(Edge>=3){Say("The edge is as fine as it goes.");return;}Edge++;break;
            case 3:
                if(Quickline>=3){Say("The reel is already fully wound.");return;}Quickline++;break;
            case 4:
                if(District+2>=LegCount){Say("The shortcut ends before the final gate.");return;}
                Chits-=cost;District+=2;GenerateDistrict();Say("The ash tender takes your chits and poles straight past one district.");return;
            default:return;
        }
        Chits-=cost;
        Say(slot==1?"Vara divides the hot ration three ways.":slot==2?"Vara fits the tempered edge.":"Lio takes three turns out of his line.");
    }
    public Vector2 Walkable(Vector2 point)
    {
        var best=QuayPaths.Walkable(point);
        if(BrokenBridge<0||Repaired)return best;
        var (a,b)=QuayPaths.Bridges[BrokenBridge];var axis=b-a;
        float t=Vector2.Dot(best-a,axis)/axis.LengthSquared();
        if(t<=.37f||t>=.63f||Vector2.Distance(best,a+axis*t)>.71f)return best;
        return best + axis*((t<.5f?.37f:.63f)-t);
    }
    public Vector2 PassengerDock=>new(Branch==0?-2.1f:2.1f,-1.95f);
    public Vector2 WeightAt(int index)
    {
        float a=Clock*1.3f+index*MathF.PI;
        return Workbench+new Vector2(MathF.Cos(a)*1.70f,MathF.Sin(a)*1.20f);
    }
    public void Tick(float dt,Vector2 direction,bool cut,bool dodge,bool hook)
    {
        if(Boarded||Phase==YardPhase.Lost)return;
        Clock+=dt;
        Swing=Decay(Swing,dt);Hook=Decay(Hook,dt);Dash=Decay(Dash,dt);Hurt=Decay(Hurt,dt);
        HookWait=Decay(HookWait,dt);DodgeWait=Decay(DodgeWait,dt);safe=Decay(safe,dt);swingDelay=Decay(swingDelay,dt);
        LineClock=Decay(LineClock,dt);
        if(direction.LengthSquared()>1)direction=Vector2.Normalize(direction);
        if(direction.LengthSquared()>.01f)Heading=direction;
        if(dodge&&DodgeWait==0){dashDirection=Unit(Heading);Dash=.22f;DodgeWait=Outfit==Loadout.Broadside?1.55f:1.05f;safe=.28f;}
        Player=Walkable(Player+(Dash>0?dashDirection*8.6f:direction*(Carrying?2.35f:2.85f))*dt);
        Mate=Walkable(Vector2.Lerp(Mate,Player-Heading*.67f+new Vector2(.22f,-.18f),Math.Min(1,dt*4.6f)));
        bool slashing=cut&&swingDelay==0&&Dash==0, hooking=hook&&HookWait==0;
        if(hooking&&!Repaired&&BrokenBridge>=0&&Near(RepairPost,1.1f)&&Chits>0)
        {
            Chits--;Repaired=true;Hook=.5f;HookWait=1;HookEnd=RepairPost;
            hooking=false;Say("The spare line holds. Both crews can cross the repaired bridge.");
        }
        bool usedHook=Finishing?FinishWork(dt,slashing,hooking):Phase==YardPhase.Work&&Work(dt,slashing,hooking);
        var nearest=Foes.MinBy(f=>Vector2.DistanceSquared(f.Position,Player));
        if(slashing)
        {
            Swing=.23f;swingDelay=.42f;
            if(nearest!=null&&Near(nearest.Position,1.85f))Heading=Unit(nearest.Position-Player);
            foreach(var enemy in Foes)
            {
                var to=enemy.Position-Player;
                if(to.Length()>(enemy.Kind==YardBeast.Guardian?1.75f:1.36f)||Vector2.Dot(Unit(to),Unit(Heading))<-.12f)continue;
                bool shield=enemy.Kind==YardBeast.Porter||enemy.Kind==YardBeast.Guardian;
                bool guarded=shield&&enemy.Stagger==0&&Vector2.Dot(enemy.Heading,-Unit(to))>.46f;
                bool covered=Foes.Any(f=>f!=enemy&&f.Kind==YardBeast.Porter&&f.Stagger==0&&Vector2.DistanceSquared(f.Position,enemy.Position)<2.25f);
                int blade=Outfit==Loadout.Broadside?3:Outfit==Loadout.Longline?-1:0;
                if(enemy.Kind==YardBeast.Guardian&&Harness)continue;
                enemy.Health-= Math.Max(1,(guarded||covered ? 2 : enemy.Stagger>0?10:6)+Edge*2+blade);
                enemy.Hit=.18f;
            }
        }
        if(Phase==YardPhase.Guardian&&Harness)
        {
            for(int i=0;i<2;i++)
            {
                if(!GuardPins[i])continue;
                if(ChargeHarness)
                {
                    if(HotPins[i]&&slashing&&Near(Locks[i],1.28f)){GuardPins[i]=false;Say("The hot bolt splits. The harness slips to one side.");}
                }
                else if(i==0&&hooking&&Near(Locks[i],2.70f))
                {GuardPins[i]=false;usedHook=true;Hook=.52f;HookEnd=Locks[i];HookWait=1.1f;Say("The first fitting is free. Break the other with your blade.");}
                else if(i==1&&slashing&&Near(Locks[i],1.25f))GuardPins[i]=false;
            }
            if(!Harness)Say("The harness is gone. The crew can reach the exposed seam.");
        }
        if(hooking&&!usedHook&&nearest!=null&&Vector2.Distance(Mate,nearest.Position)<(Outfit==Loadout.Longline?5.3f:4.0f))
        {
            bool caught=Attacks.RemoveAll(a=>a.Source==nearest&&!a.Fired&&!(Harness&&ChargeHarness))>0;
            Hook=.42f;HookWait=5.1f-Quickline*.85f+(Outfit==Loadout.Longline?-1:Outfit==Loadout.Lifeboat?1:0);HookEnd=nearest.Position;
            if(nearest.Kind!=YardBeast.Guardian||!Harness)nearest.Health-=caught?12:3;nearest.Stagger=caught?1.35f:.45f;
            nearest.Rush=0;nearest.Wait=.5f;nearest.Hit=.16f;
            if(caught)Say("Lio has the line. Strike the exposed seam!");
        }
        for(int i=Foes.Count-1;i>=0;i--)
        {
            var beast=Foes[i];
            if(beast.Health<=0)
            {
                int count=beast.Kind==YardBeast.Guardian?6:2;
                for(int k=0;k<count;k++)
                {
                    float a=k*MathF.Tau/count;
                    SilverDrops.Add(Walkable(beast.Position+new Vector2(MathF.Cos(a),MathF.Sin(a))*.41f));
                }
                Attacks.RemoveAll(a=>a.Source==beast);
                Foes.RemoveAt(i);
                if(beast.Kind==YardBeast.Guardian)
                {
                    Phase=YardPhase.Keys;KeyPlace=beast.Position;BeginFinal();
                }
                else if(Foes.Count==0 && Phase==YardPhase.BranchFight)BeginJob();
                else if(Foes.Count==0 && Phase==YardPhase.GateFight)
                {
                    Phase=YardPhase.Camp;Chits++;Say("The slip is ours. At the striped tarp, trade chits for rations, an edge or a faster reel.");
                }
                continue;
            }
            BeastTurn(beast,dt);
        }
        for(int i=Attacks.Count-1;i>=0;i--)
        {
            var a=Attacks[i];a.Age+=dt;
            if(a.Age>=a.Lead&&!a.Fired)
            {
                a.Fired=true;
                if(Harness&&ChargeHarness&&a.Shape==AttackShape.Lane&&a.Source.Kind==YardBeast.Guardian)
                    for(int pin=0;pin<2;pin++)if(GuardPins[pin]&&a.Contains(Locks[pin])){HotPins[pin]=true;Say("The charge drove a pin red-hot. Cut it with J.");}
                if(a.Rush){a.Source.Rush=.42f;a.Source.RushTo=Walkable(a.Target);}
            }
            if(a.Fired&&!a.Hurt&&a.Contains(Player)&&safe==0){Damage(a.Source.Kind==YardBeast.Guardian?2:1);a.Hurt=true;}
            if(a.Age>=a.Lead+a.Active)Attacks.RemoveAt(i);
        }
        for(int i=SilverDrops.Count-1;i>=0;i--)if(Near(SilverDrops[i],.90f)){SilverDrops.RemoveAt(i);Silver++;}
        if(Health<=0){Phase=YardPhase.Lost;Say("Lio cuts the line. The crew gets you clear with the silver.");}
    }
    void BeginFinal()
    {
        Braced=false;PassengerFree=false;trail.Clear();billetVelocity=Vector2.Zero;
        Passenger=QuayPaths.Summit+new Vector2(-2.15f,-1.26f);
        Billet=FinalSite+new Vector2(-.79f,.59f);
        Say(FinalStep.Instruction+".");
    }
    void AdvanceFinal()
    {
        Silver+=2;
        if(++FinalIndex==contract.Length){Phase=YardPhase.Departure;Say("The work is done. Board the marked ferry together.");return;}
        Phase=YardPhase.Release;BeginFinal();
    }
    bool FinishWork(float dt,bool cut,bool hook)
    {
        bool used=false;
        switch(FinalStep.Action)
        {
            case LandingAction.Cut when cut&&Near(FinalSite,1.3f):AdvanceFinal();break;
            case LandingAction.Haul when hook&&Near(FinalSite,3.1f):
                Hook=.53f;HookWait=1.0f;HookEnd=FinalSite;used=true;AdvanceFinal();break;
            case LandingAction.Brace when hook&&Near(FinalSite,2.65f):
                Hook=.55f;HookWait=1;HookEnd=FinalSite;Braced=true;used=true;Say("Lio holds the weight. Use the free lever with E.");break;
            case LandingAction.Seat:
                if(hook&&Near(Billet,3.3f)){Hook=.44f;HookWait=1;HookEnd=Billet;billetVelocity=Unit(Player-Billet)*3.6f;used=true;}
                if(cut&&Near(Billet,1.3f))billetVelocity=Unit(Billet-Player)*4.8f;
                Billet=Walkable(Billet+billetVelocity*dt);billetVelocity*=MathF.Exp(-5*dt);
                if(Vector2.Distance(Billet,FinalSite)<.40f)AdvanceFinal();
                break;
            case LandingAction.Guide when PassengerFree:
                FollowWorker(dt);
                if(Vector2.Distance(Passenger,DeliverTo)<1.25f)AdvanceFinal();
                break;
        }
        return used;
    }
    void FollowWorker(float dt)
    {
        if(Vector2.DistanceSquared(lastTrail,Player)>.055f){lastTrail=Player;trail.Enqueue(Player);}
        if(trail.TryPeek(out var next)&&Vector2.Distance(Passenger,Player)>.82f)
        {
            var step=next-Passenger;
            if(step.Length()<.065f)trail.Dequeue();else Passenger+=Unit(step)*Math.Min(step.Length(),dt*(Outfit==Loadout.Lifeboat?4.25f:3.4f));
        }
    }
    bool Work(float dt,bool cut,bool hook)
    {
        bool used=false;
        if(Carrying)return false;
        switch(Job)
        {
            case LandingJob.Nets when hook:
                for(int i=0;i<3;i++)if(!Secured[i]&&Near(Float(i),2.30f))
                {
                    HookEnd=Float(i);Hook=.5f;HookWait=.95f;used=true;Secured[i]=true;JobStep();break;
                }
                break;
            case LandingJob.Mould:
                if(hook&&Near(Billet,3.5f)){HookEnd=Billet;Hook=.4f;HookWait=1;used=true;billetVelocity=Unit(Player-Billet)*3.8f;}
                if(cut&&Near(Billet,1.3f))billetVelocity=Unit(Billet-Player)*4.8f;
                Billet+=billetVelocity*dt;billetVelocity*=MathF.Exp(-5*dt);
                var norm=(Billet-Workbench)/new Vector2(1.7f,1.48f);
                if(norm.LengthSquared()>1)Billet=Workbench+Vector2.Normalize(norm)*new Vector2(1.7f,1.48f);
                if(Vector2.Distance(Billet,Mould)<.43f){Carrying=true;Say("The bronze is seated. Take the finished casting to the upper slip.");}
                break;
            case LandingJob.Escort when PassengerFree:
                FollowWorker(dt);
                if(!Intercept&&Vector2.Distance(Passenger,Workbench)>2.45f)
                {
                    Intercept=true;SpawnWatch(PassengerDock,false);
                    Say("The toll watch is waiting at the approach. Make room for the worker to pass.");
                }
                if(Foes.Count==0&&Vector2.Distance(Passenger,PassengerDock)<1.5f)CompleteJob();
                break;
            case LandingJob.Capstans:
                if(hook&&!Anchored&&Near(Workbench,2.05f))
                {Anchored=true;Hook=.4f;HookWait=.95f;HookEnd=Workbench;used=true;Say("The cable is fast. Turn the marked winch with E.");}
                if(safe==0&&(Near(WeightAt(0),.45f)||Near(WeightAt(1),.45f)))Damage(1);
                break;
            case LandingJob.Breakers when cut||hook:
                for(int i=0;i<3;i++)if(!Secured[i]&&(i==1?hook:cut)&&Near(Mark(i),i==1?2.85f:1.25f))
                {
                    if(i==1){used=true;Hook=.45f;HookWait=1;HookEnd=Mark(i);}
                    Secured[i]=true;JobStep();break;
                }
                break;
        }
        return used;
    }
    void Damage(int count){Health=Math.Max(0,Health-count);safe=.90f;Hurt=.22f;}
    void BeastTurn(YardBeastState beast,float dt)
    {
        beast.Hit=Decay(beast.Hit,dt);
        if(beast.Stagger>0){beast.Stagger=Decay(beast.Stagger,dt);return;}
        if(beast.Rush>0)
        {
            beast.Rush=Decay(beast.Rush,dt);
            beast.Position=Walkable(Vector2.Lerp(beast.Position,beast.RushTo,Math.Min(1,dt*12)));
            return;
        }
        var to=Player-beast.Position;
        bool boss=beast.Kind==YardBeast.Guardian;
        if(boss&&!beast.Enraged&&beast.Health<=beast.Maximum*.48f)
        {
            beast.Enraged=true;beast.Wait=.6f;GuardPins[0]=GuardPins[1]=true;
            Say(ChargeHarness?"The harness has chained itself to two rivets. Stand behind each brass pin, dodge the rush, then cut the hot metal.":"Two fittings lock the shell. Hook the west one with K, then cut the east one with J.");
        }
        float clearance=boss?1.06f:.48f;
        if(to.LengthSquared()<clearance*clearance)Player=Walkable(beast.Position+Unit(to)*clearance);
        if(Attacks.Any(a=>a.Source==beast&&!a.Fired))return;
        beast.Heading=Unit(Player-beast.Position);
        if(beast.Wait>0){beast.Wait=Decay(beast.Wait,dt);return;}
        float reach=beast.Kind switch { YardBeast.Scrapper or YardBeast.Porter=>1.28f,YardBeast.Slinger=>4.6f,YardBeast.Guardian when Harness&&ChargeHarness=>6.1f,_=>4.2f };
        if(to.Length()>reach)
        {
            float speed=beast.Kind switch{YardBeast.Porter=>1.22f,YardBeast.Skater=>2.25f,_=>1.75f};
            beast.Position=Walkable(beast.Position+beast.Heading*(dt*speed));
            return;
        }
        beast.Pattern++;
        if(boss)GuardianAttack(beast);
        else
        {
            switch(beast.Kind)
            {
                case YardBeast.Scrapper:Fan(beast,1.55f,.12f,.74f);break;
                case YardBeast.Slinger:Disc(beast,Player,1.01f,.95f);break;
                case YardBeast.Porter:Ring(beast,beast.Position,.36f,1.87f,1.03f);break;
                case YardBeast.Skater:Lane(beast,beast.Position,beast.Position+beast.Heading*3.9f,.44f,.85f,true);break;
            }
            beast.Wait=1.00f+(beast.Kind==YardBeast.Porter?.6f:.25f);
        }
    }
    void GuardianAttack(YardBeastState b)
    {
        var h=b.Heading;
        var side=new Vector2(-h.Y,h.X);
        var p=b.Position;
        float lead=b.Enraged?.80f:1.07f;
        bool second=b.Pattern%2==0;
        if(Harness&&ChargeHarness)
        {
            Lane(b,p,p+h*6.4f,.82f,.98f,true);b.Wait=1.18f;return;
        }
        if(Order.Boss switch {"Stamp Beetle" or "Freezer Dog" or "Cradle Hornet" or "Ward Lamprey" or "Tally Jack" or "The Brass Balance" or "The Plumb Serpent" => true,_=>false})
        {
            switch(Order.Boss)
            {
                case "Stamp Beetle":Disc(b,Player,1.43f,lead);if(second||b.Enraged)Disc(b,Player+h*1.6f,1.20f,lead+.45f);break;
                case "Freezer Dog":Lane(b,p,p+h*4.9f,.52f,lead,true);if(second)Disc(b,p,1.48f,lead+.40f);break;
                case "Cradle Hornet":Lane(b,p,p+h*5.2f,.40f,lead,true);if(second||b.Enraged)Lane(b,p+side*.78f,p+h*5.2f+side*.78f,.37f,lead+.34f);break;
                case "Ward Lamprey":Fan(b,2.43f,.42f,lead);if(second||b.Enraged)Ring(b,p,.64f,2.10f,lead+.49f);break;
                case "Tally Jack":Fan(b,2.66f,.22f,lead);Lane(b,p-side*1.5f,p+side*1.5f,.48f,lead+.58f);break;
                case "The Brass Balance":Disc(b,Player+side*.81f,1.14f,lead);Disc(b,Player-side*.81f,1.14f,lead+.45f);break;
                default:Lane(b,p,p+h*4.6f,.59f,lead,true);Ring(b,Player,1.09f,2.4f,lead+.54f);break;
            }
            b.Wait=b.Enraged?.83f:1.21f;return;
        }
        switch(Region.Climate)
        {
            case IslandClimate.Kiln:
                if(second)Fan(b,2.85f,-.14f,lead);
                else Lane(b,p,p+h*5.2f,.75f,lead,true);
                if(b.Enraged)Disc(b,Player+side*1.0f,.95f,lead+.52f);
                break;
            case IslandClimate.Delta:
                if(second)Lane(b,p,p+h*5.0f,.44f,lead);
                else {Disc(b,Player,1.1f,lead);Disc(b,Player-h*1.6f,.9f,lead+.42f);}
                if(b.Enraged)Disc(b,Player+h*1.3f,1,lead+.78f);
                break;
            case IslandClimate.Orchard:
                Ring(b,p,second?1.1f:2.35f,second?2.5f:4.2f,lead);
                if(b.Enraged||second)Disc(b,Player+side*.7f,1.1f,lead+.5f);
                break;
            case IslandClimate.Shelf:
                Disc(b,Player,1.4f,lead);if(second)Lane(b,p,Player+h*.7f,.70f,lead+.24f,true);
                if(b.Enraged)Disc(b,p,1.55f,lead+.70f);
                break;
            case IslandClimate.Loom:
                Lane(b,Player-side*2.8f,Player+side*2.8f,.43f,lead);
                Lane(b,Player-h*2.7f,Player+h*2.7f,.39f,lead+.40f);
                if(b.Enraged)Ring(b,p,1.6f,2.8f,lead+.68f);
                break;
            case IslandClimate.Reef:
                Ring(b,p,1.65f,3.35f,lead);Disc(b,p,1.55f,lead+.56f);
                if(b.Enraged)Ring(b,p,2.95f,4.5f,lead+.94f);
                break;
            case IslandClimate.Court:
                Lane(b,p,p+h*4.6f,.60f,lead,true);
                if(second||b.Enraged)Fan(b,2.6f,.18f,lead+.47f);
                break;
            case IslandClimate.Stars:
                var diagonal=Unit(h+side);
                Lane(b,Player-diagonal*3.1f,Player+diagonal*3.1f,.49f,lead);
                if(second||b.Enraged){diagonal=Unit(h-side);Lane(b,Player-diagonal*3.1f,Player+diagonal*3.1f,.55f,lead+.49f);}
                break;
        }
        b.Wait=b.Enraged?.86f:1.34f;
    }
    void Disc(YardBeastState b,Vector2 p,float r,float lead)=>Attacks.Add(new(b,AttackShape.Disc,p,p,r,0,lead,.25f));
    void Ring(YardBeastState b,Vector2 p,float inner,float outer,float lead)=>Attacks.Add(new(b,AttackShape.Ring,p,p,outer,inner,lead,.26f));
    void Fan(YardBeastState b,float r,float cosine,float lead)=>Attacks.Add(new(b,AttackShape.Fan,b.Position,b.Position+b.Heading,r,cosine,lead,.22f));
    void Lane(YardBeastState b,Vector2 from,Vector2 to,float radius,float lead,bool rush=false)=>Attacks.Add(new(b,AttackShape.Lane,from,to,radius,0,lead,.27f,rush));
    static float Decay(float v,float dt)=>Math.Max(0,v-dt);
    static Vector2 Unit(Vector2 v)=>v.LengthSquared()>.0001f?Vector2.Normalize(v):Vector2.UnitY;
}
