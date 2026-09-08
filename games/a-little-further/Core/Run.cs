using System.Numerics;
namespace Further.Core;
public enum RunMode { Sailing, Exploring, Choosing, Dead }
public enum Role { Gunner, Stormcaller, Cook, Duelist, Harpooner, Tidekeeper }
public sealed class Ship
{
    public Vector2 Position=new(0,-180),Velocity;
    public double OriginX,OriginZ;
    public float Heading,Throttle,AngularVelocity,Height,VerticalVelocity,Pitch,Roll;
}
public sealed class Mate(Role role)
{
    public Role Role=role;
    public int Level=1;
    public float Cooldown, BurstClock;
    public int Shots;
    public string Name => Role switch {Role.Gunner=>"Flint",Role.Stormcaller=>"Wren",Role.Cook=>"Biscuit",Role.Duelist=>"Finch",Role.Harpooner=>"Reef",_=>"Moss"};
    public string Effect => Role switch {Role.Gunner=>"Volley fire · stronger against marked foes",Role.Stormcaller=>"Chain sparks · marks enemies",Role.Cook=>"Broadside bombs · heals on kills",Role.Duelist=>"Quick blades · executes wounded",Role.Harpooner=>"Harpoons · shatter chilled foes",_=>"Chilling aura · slows the horde"};
}
public sealed class Foe(int id,Vector2 position,int kind,float hp)
{
    public int Id=id,Kind=kind;
    public Vector2 Position=position,Knockback;
    public float Hp=hp,MaxHp=hp,Windup,Cooldown=.8f,Flash;
    public bool Marked;
    public float Chilled;
}
public readonly record struct Hit(Vector2 From,Vector2 To,float Damage,int Kind,bool Kill);
public readonly record struct Command(Vector2 Move,bool Dodge=false,bool Jump=false,bool HoldJump=false,bool Interact=false,bool Boost=false,bool Provision=false);
public sealed class Run
{
    public World World {get;}
    public Ship Ship {get;}=new();
    public RunMode Mode=RunMode.Sailing;
    public Vector2 Position,Velocity;
    public float Height,VerticalSpeed,Health=100,Stamina=1,DodgeTime,DodgeCooldown,Invincible,Heading;
    public double Time,ExplorationTime;
    public int Gold,Kills,Shrines,IslandsVisited,ShiftCount;
    public bool IsGliding=>Mode==RunMode.Exploring && airTime>PrivateSources.GlideDelay && heldGlide>PrivateSources.GlideHold && Stamina>0;
    public float ShrineSeconds=>shrineActive?shrineBattle:0;
    public float Threat=>1+(float)ExplorationTime/220+Shrines*.45f;
    public List<Mate> Crew {get;}=[new(Role.Gunner)];
    public List<Foe> Enemies {get;}=[];
    public List<Hit> Hits {get;}=[];
    public HashSet<Cell> Visited {get;}=[];
    public HashSet<Cell> Claimed {get;}=[];
    public HashSet<(Cell,int)> Treasure {get;}=[];
    public Island? Current;
    public string Notice="A fair wind. A fresh start.",ChoiceTitle="";
    public float NoticeTime=5;
    public Role[] Offers=[];
    public int SelectedReplacement;
    public Vector2 LastShift;
    public Action? Shifted;
    readonly Random random;
    readonly CombatTuning tuning;
    float spawnClock=4,captainClock,airTime,jumpClock,heldGlide,shrineBattle;
    int nextId;
    float lightningClock;
    bool shrineActive;
    IReadOnlyList<Decoration> scenery=[];
    Vector2[] treasureLocations=[];
    public Run(int seed,CombatTuning tuning){this.tuning=tuning;World=new(seed);random=new(seed);Position=Ship.Position;}
    public void Say(string s){Notice=s;NoticeTime=4;}
    public void Tick(float dt,Command input)
    {
        Hits.Clear();LastShift=Vector2.Zero;
        if(Mode is RunMode.Dead or RunMode.Choosing)return;
        dt=Math.Clamp(dt,0,.05f);Time+=dt;NoticeTime-=dt;Invincible=MathF.Max(0,Invincible-dt);DodgeCooldown=MathF.Max(0,DodgeCooldown-dt);jumpClock-=dt;
        if(Mode==RunMode.Sailing)
        {
            var old=Ship.Position;var helm=PrivateSources.AvoidShore(Ship,input.Move.Y,input.Move.X,World.Height);PrivateSources.Sail(Ship,dt,helm.Throttle,helm.Steer,input.Boost);
            if(World.Height(Ship.Position)>-.3f){Ship.Position=old;Ship.Velocity*=.3f;}
            PrivateSources.Buoy(Ship,Time,dt);Position=Ship.Position;Height=Ship.Height;Heading=Ship.Heading;
            if(input.Interact)TryLand();
        }
        else
        {
            ExplorationTime+=dt;MoveOnLand(dt,input);Combat(dt);
            if(input.Interact)Interact();
            if(input.Provision)Provision();
            Collect();
        }
        if(Health<=0){Health=0;Mode=RunMode.Dead;Enemies.Clear();Say("The sea keeps no checkpoints.");}
        if(Position.Length()>2400)ShiftOrigin();
    }
    void ShiftOrigin()
    {
        var shift=new Vector2(MathF.Round(Position.X/World.ChunkSize)*World.ChunkSize,MathF.Round(Position.Y/World.ChunkSize)*World.ChunkSize);
        World.Origin=new(World.Origin.X+(int)(shift.X/World.ChunkSize),World.Origin.Z+(int)(shift.Y/World.ChunkSize));
        Position-=shift;Ship.Position-=shift;Ship.OriginX+=shift.X;Ship.OriginZ+=shift.Y;foreach(var e in Enemies)e.Position-=shift;
        if(Current!=null)Current=World.IslandAt(Current.Cell);
        LastShift=shift;ShiftCount++;Shifted?.Invoke();
    }
    public Island Nearest=>World.IslandAt(World.CellAt(Position));
    public bool CanLand=>Mode==RunMode.Sailing && Vector2.Distance(Position,Nearest.Landing)<19;
    void TryLand()
    {
        if(!CanLand){Say("Find the amber landing lantern on the beach.");return;}
        Current=Nearest;scenery=IslandLayout.Scenery(Current);treasureLocations=Enumerable.Range(0,IslandLayout.TreasureCount).Select(i=>IslandLayout.Treasure(Current,i)-Current.Center).ToArray();Position=Current.Landing;Height=World.Height(Position);Velocity=Vector2.Zero;Mode=RunMode.Exploring;Ship.Velocity=Vector2.Zero;
        if(Visited.Add(Current.Cell)){IslandsVisited++;Gold+=5;}
        Say(Current.Name+" · Follow the gold trail to the summit shrine.");spawnClock=IslandsVisited==1?28:12;
    }
    void MoveOnLand(float dt,Command input)
    {
        Vector2 dir=input.Move;if(dir.LengthSquared()>1)dir=Vector2.Normalize(dir);
        float ground=World.Height(Position);bool grounded=Height<=ground+.06f;
        airTime=grounded?0:airTime+dt;
        if(input.Dodge && DodgeCooldown<=0 && dir.LengthSquared()>.01f){DodgeTime=.23f;DodgeCooldown=1.1f;Invincible=.3f;Velocity=dir*19;}
        DodgeTime-=dt;
        if(DodgeTime<=0)Velocity=PrivateSources.Walk(Velocity,dir,input.Boost?8.2f:6.3f,dt,!grounded);
        Vector2 next=Position+Velocity*dt;
        if(Current!=null && grounded)next=IslandLayout.ResolveObstacles(next,Current,scenery);float nextGround=World.Height(next);
        if(nextGround<-.25f){Velocity*=.6f;next=Position;}
        bool climbing=nextGround-ground>.22f && Stamina>0 && input.HoldJump;
        if(nextGround-ground<.62f || !grounded || climbing)Position=next;
        if(climbing){Height=nextGround;Stamina=MathF.Max(0,Stamina-dt*.15f);}
        if(input.Jump && (grounded||airTime<PrivateSources.CoyoteTime) && jumpClock<=0){VerticalSpeed=9;Height+=.1f;jumpClock=PrivateSources.JumpCooldown;}
        heldGlide=input.HoldJump?heldGlide+dt:0;
        VerticalSpeed-=23*dt;
        if(airTime>PrivateSources.GlideDelay && heldGlide>PrivateSources.GlideHold && input.HoldJump && Stamina>0){VerticalSpeed=MathF.Max(PrivateSources.GlideFall,VerticalSpeed);Stamina=MathF.Max(0,Stamina-dt*.17f);}
        Height+=VerticalSpeed*dt;ground=World.Height(Position);
        if(Height<ground){Height=ground;VerticalSpeed=0;Stamina=MathF.Min(1,Stamina+dt*.8f);}
        if(Velocity.LengthSquared()>.1f)Heading=MathF.Atan2(Velocity.X,Velocity.Y);
    }
    public Vector2 TreasureAt(int index)
    {
        return Current!.Center+treasureLocations[index];
    }
    void Collect()
    {
        if(Current==null)return;
        for(int i=0;i<IslandLayout.TreasureCount;i++)if(!Treasure.Contains((Current.Cell,i)) && Vector2.Distance(Position,TreasureAt(i))<2.2f){Treasure.Add((Current.Cell,i));int reward=i<8?8:24;Gold+=reward;Say(i<8?"+8 doubloons":"Cache found · +24 doubloons");}
    }
    public string Prompt
    {
        get
        {
            if(Mode==RunMode.Sailing)return CanLand?"E  ·  Drop anchor at "+Nearest.Name:"";
            if(Mode!=RunMode.Exploring || Current==null)return "";
            if(shrineActive)return $"Defend the bell · {MathF.Ceiling(shrineBattle)}s";
            if(Vector2.Distance(Position,Current.Landing)<5)return "E  ·  Board ship     F  ·  Provision crew (40 gold)";
            if(Vector2.Distance(Position,Current.Shrine)<5)return shrineActive?$"Defend the shrine · {MathF.Ceiling(shrineBattle)}s":Claimed.Contains(Current.Cell)?"The shrine is quiet":"E  ·  Ring the Corsair’s Bell";
            return "";
        }
    }
    void Interact()
    {
        if(Current==null)return;
        if(Vector2.Distance(Position,Current.Landing)<5){Mode=RunMode.Sailing;Position=Ship.Position;Height=Ship.Height;Enemies.Clear();shrineActive=false;return;}
        if(Vector2.Distance(Position,Current.Shrine)<5 && !Claimed.Contains(Current.Cell) && !shrineActive){shrineActive=true;shrineBattle=24;spawnClock=0;Say("The bell calls the drowned. Hold your ground!");}
    }
    public void Provision()
    {
        if(Mode!=RunMode.Exploring || Current==null || Vector2.Distance(Position,Current.Landing)>6)return;
        if(Gold<40){Say("40 doubloons provision the crew and restore 25 health.");return;}
        Gold-=40;Health=MathF.Min(100,Health+25);var mate=Crew.OrderBy(m=>m.Level).First();mate.Level++;Say(mate.Name+" gains a rank. Fresh supplies, fresh courage.");
    }
    void Combat(float dt)
    {
        if(Current==null)return;
        spawnClock-=dt;
        if(spawnClock<=0 && Enemies.Count<Math.Min(72,12+(int)(Threat*8)))
        {
            spawnClock=PrivateSources.SpawnInterval(Threat,shrineActive);
            int count=shrineActive?2:1;
            for(int k=0;k<count && Enemies.Count<Math.Min(72,12+(int)(Threat*8));k++)
            {
                float angle=(float)random.NextDouble()*MathF.Tau;Vector2 p=Position+new Vector2(MathF.Sin(angle),MathF.Cos(angle))*random.Next(14,21);
                if(World.Height(p)>.2f && Vector2.Distance(p,Current.Center)<Current.Radius*.9f)
                {
                    int kind=random.NextDouble()<.2?1:0;float health=kind==1?tuning.Brute.Health:tuning.Sailor.Health;
                    Enemies.Add(new(++nextId,p,kind,health+Threat*6));
                }
            }
        }
        if(shrineActive){shrineBattle-=dt;if(shrineBattle<=0){shrineActive=false;Claimed.Add(Current.Cell);Shrines++;Gold+=30;Health=MathF.Min(100,Health+18);Offers=Enum.GetValues<Role>().OrderBy(_=>random.Next()).Take(3).ToArray();ChoiceTitle="The bell remembers your courage";Mode=RunMode.Choosing;return;}}
        captainClock-=dt;lightningClock-=dt;
        if(captainClock<=0){var target=NearestFoe(Position,4.6f);if(target!=null){captainClock=tuning.Sword.Cooldown;Strike(target,tuning.Sword.Damage,0,Position);}}
        for(int i=0;i<Crew.Count;i++)
        {
            Mate m=Crew[i];m.Cooldown-=dt;m.BurstClock-=dt;
            if(m.Role==Role.Gunner && m.Shots>0 && m.BurstClock<=0)
            {
                var shot=NearestFoe(Position,17);if(shot!=null){Strike(shot,tuning.Gun.Damage*(shot.Marked?1.65f:1)*(1+(m.Level-1)*.25f),1,Position);m.Shots--;m.BurstClock=tuning.Gun.BurstTime/Math.Max(1,tuning.Gun.Projectiles);}
            }
            if(m.Cooldown>0)continue;
            float range=m.Role==Role.Duelist?6:16;var e=NearestFoe(Position,range);if(e==null)continue;
            Vector2 from=Position+new Vector2(MathF.Sin(i*2f),MathF.Cos(i*2f))*2;
            var attack=m.Role switch{Role.Gunner=>tuning.Gun,Role.Stormcaller=>tuning.Spark,Role.Cook=>tuning.Bomb,Role.Harpooner=>tuning.Harpoon,Role.Tidekeeper=>tuning.Frost,_=>tuning.Sword};
            float damage=attack.Damage*(1+(m.Level-1)*.25f);
            m.Cooldown=(attack.Cooldown+(m.Role==Role.Gunner?attack.BurstTime:0))/(1+(m.Level-1)*.08f);
            if(m.Role==Role.Gunner){m.Shots=attack.Projectiles-1;m.BurstClock=attack.BurstTime/Math.Max(1,attack.Projectiles);}
            if(m.Role==Role.Duelist && e.Hp<e.MaxHp*.4f)damage*=2;
            if(m.Role==Role.Gunner && e.Marked)damage*=1.65f;
            if(m.Role==Role.Harpooner && e.Chilled>0)damage*=2.2f;
            if(m.Role==Role.Tidekeeper){foreach(var nearby in Enemies.Where(x=>Vector2.Distance(Position,x.Position)<9))nearby.Chilled=2.4f;}
            Strike(e,damage,(int)m.Role+1,from);
            if(m.Role==Role.Stormcaller){e.Marked=true;foreach(var other in Enemies.Where(x=>x!=e && Vector2.Distance(x.Position,e.Position)<6).Take(2).ToArray()){other.Marked=true;Strike(other,damage*.65f,2,e.Position);}}
            if(m.Role==Role.Cook)foreach(var other in Enemies.Where(x=>x!=e && Vector2.Distance(x.Position,e.Position)<4).ToArray())Strike(other,damage*.7f,3,e.Position);
        }
        foreach(var e in Enemies)
        {
            if(e.Hp<=0)continue;e.Flash=MathF.Max(0,e.Flash-dt);e.Chilled=MathF.Max(0,e.Chilled-dt);e.Cooldown-=dt;Vector2 delta=Position-e.Position;float distance=delta.Length();
            Vector2 dir=distance>.01f?delta/distance:Vector2.Zero;
            if(e.Windup>0)
            {
                e.Windup-=dt;if(e.Windup<=0){if(distance<(e.Kind==1?4.6f:2.8f) && Invincible<=0){float damage=e.Kind==1?tuning.Brute.Damage:tuning.Sailor.Damage;Health-=damage;Invincible=.65f;Hits.Add(new(e.Position,Position,damage,-1,false));}e.Cooldown=e.Kind==1?2.1f:1.5f;}
            }
            else if(distance<(e.Kind==1?4:2.1f) && e.Cooldown<=0)e.Windup=e.Kind==1?.8f:.5f;
            else if(distance>1.7f){var next=e.Position+dir*(e.Kind==1?tuning.Brute.Speed:tuning.Sailor.Speed)*(e.Chilled>0?.5f:1)*dt;e.Position=World.Height(next)>0?next:e.Position;}
            e.Position+=e.Knockback*dt;e.Knockback*=MathF.Exp(-9*dt);
        }
        Enemies.RemoveAll(e=>e.Hp<=0);
    }
    Foe? NearestFoe(Vector2 p,float radius)=>PrivateSources.ClosestEnemy(Enemies,p,radius);
    void Strike(Foe e,float damage,int kind,Vector2 from)
    {
        if(e.Hp<=0)return;e.Hp-=damage;e.Flash=.13f;Vector2 delta=e.Position-from;e.Knockback=delta.LengthSquared()>.01?Vector2.Normalize(delta)*7:Vector2.Zero;
        bool killed=e.Hp<=0;Hits.Add(new(from,e.Position,damage,kind,killed));
        if(killed){Kills++;Gold+=2;
            if(e.Marked && kind==1 && lightningClock<=0 && Crew.Any(m=>m.Role==Role.Stormcaller))
            {
                lightningClock=PrivateSources.LightningCooldown;
                foreach(var other in Enemies.Where(x=>x!=e && x.Hp>0 && Vector2.Distance(x.Position,e.Position)<PrivateSources.LightningRadius).ToArray())Strike(other,tuning.Spark.Damage*PrivateSources.LightningDamageMultiplier,2,e.Position);
                Say("STORM BROADSIDE · Marked kill unleashes chain lightning");
            }if(Crew.Any(m=>m.Role==Role.Cook))Health=MathF.Min(100,Health+1.5f);}
    }
    public void Choose(int index,int replace=0)
    {
        if(Mode!=RunMode.Choosing||index<0||index>=Offers.Length)return;
        Role role=Offers[index];var existing=Crew.FirstOrDefault(m=>m.Role==role);
        if(existing!=null){existing.Level++;Say(existing.Name+" rises to rank "+existing.Level);}
        else if(Crew.Count<4){Crew.Add(new(role));Say(Crew[^1].Name+" joins your crew.");}
        else {Crew[Math.Clamp(replace,0,3)]=new(role);Say("A new hand aboard. A new possibility.");}
        Mode=RunMode.Exploring;Invincible=2;
    }
}
