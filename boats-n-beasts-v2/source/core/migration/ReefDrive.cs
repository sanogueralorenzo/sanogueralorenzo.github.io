using System.Numerics;

namespace BoatsNBeasts.Core;

public enum CalfMood { Listening, Following, Grazing, Home }

public sealed class ReefCalf(string name,Vector2 position,int[] song,int color)
{
    public string Name {get;}=name;
    public int Dye {get;}=color;
    public int[] Song {get;}=song;
    public Vector2 Position=position, Bow=-Vector2.UnitY;
    public CalfMood Mood;
    public float Nerve=100, Spirit=100, Hit, Hush;
    public int Notes;
    public readonly Queue<Vector2> Wake=new();
    public Vector2 LastTurn=position;
}

public sealed class ReefDrive
{
    public Voyage Ship {get;}
    public CampaignOrder Order {get;}
    public ReefCalf[] Herd {get;}
    public Vector2 Nursery {get;}
    public Vector2[] Grass {get;}
    public int Purse {get;private set;}
    public int Kelp {get;private set;}=2;
    public int Kits {get;private set;}
    public bool Won {get;private set;}
    public bool Lost => Ship.Mode==VoyageMode.Defeat || Herd.Any(c=>c.Spirit<=0);
    public float Voice {get;private set;}
    public float CastTime {get;private set;}
    public int Home => Herd.Count(c=>c.Mood==CalfMood.Home);
    public ReefCalf? Singer => Herd.Where(c=>c.Mood is CalfMood.Listening or CalfMood.Grazing)
        .Where(c=>Vector2.Distance(c.Position,Ship.Position)<390).MinBy(c=>Vector2.DistanceSquared(c.Position,Ship.Position));
    public string Report {get;private set;}="Find a calf and answer its call. The nursery ship is waiting in the eastern lee.";
    public float Speech {get;private set;}=5;
    public float Time {get;private set;}
    readonly bool[] cut;
    readonly Loadout outfit;
    readonly OceanWorld scout;
    float sailed, patrol, payout;
    int wave;
    public ReefDrive(CampaignOrder order,int seed,int stores,Loadout outfit, BoatKind vessel = BoatKind.Cutter)
    {
        Order=order;this.outfit=outfit;var rng=new Random(seed);scout=new((uint)seed);
        Ship=new((uint)seed,vessel,1){Charted=true,BroadsideRig=outfit==Loadout.Broadside,HullRank=Math.Clamp(stores,0,2)};
        Ship.Weapons[0]=Math.Max(1,Ship.Weapons[0]);
        Ship.Health=Ship.MaxHealth;Kits=outfit==Loadout.Lifeboat?3:1;
        Vector2 origin=Ship.Position;
        int sign=rng.Next(2)==0?1:-1;
        Nursery=Clear(origin+new Vector2(1900+rng.Next(400),sign*480),200);
        string[][] names=[
            ["Sprig","Fennel","Bramble"],["Minnowglass","Bead","Stopper"],["Waxfoot","Moth","Tallow"],["Snore","Blanket","Drowse"],
            ["Button","Tincup","Spangle"],["Rattle","Rest","Downbeat"],["Pitchpot","Hob","Shingle"],["Thimble","Pebble","Little Bell"]];
        int coast=Math.Clamp(order.Tier-9,0,7),count=order.Tier>=13?3:2;
        Herd=new ReefCalf[count];Grass=new Vector2[count+1];cut=new bool[Grass.Length];
        for(int i=0;i<count;i++)
        {
            Vector2 home=origin+new Vector2(-950+i*1050+rng.Next(-290,291),sign*((i%2==0?-1:1)*(1450+i*320+rng.Next(500))));
            int[] song=new int[order.Tier>=14?4:3];for(int j=0;j<song.Length;j++)song[j]=1+rng.Next(3);
            Herd[i]=new(names[coast][i],Clear(home,160),song,coast+i);
            Grass[i]=Clear(Vector2.Lerp(home,Nursery,.3f)+new Vector2(270,320),125);
        }
        Grass[^1]=Clear(origin+new Vector2(-440,270),105);
    }
    Vector2 Clear(Vector2 guess,int radius)
    {
        scout.Stream(guess);
        for(int ring=0;ring<26;ring++)
            for(int j=0;j<(ring==0?1:14);j++)
            {
                float a=j*MathF.Tau/14+ring*.17f;
                var pt=guess+new Vector2(MathF.Cos(a),MathF.Sin(a))*ring*62;
                if(scout.IsWater(pt,radius))return pt;
            }
        return StartingArea.Spawn;
    }
    public bool Cut(int index)=>cut[index];
    public void Say(string line){Report=line;Speech=5;}
    public void Note(int note)
    {
        if(Won||Lost||Ship.Mode!=VoyageMode.Sailing)return;
        if(Singer is not {} calf){Say("Come alongside a listening calf to answer its call.");return;}
        if(note!=calf.Song[calf.Notes])
        {
            calf.Notes=note==calf.Song[0]?1:0;
            Say($"{calf.Name} cocks one ear. Listen again.");return;
        }
        calf.Notes++;
        if(calf.Notes<calf.Song.Length)return;
        if(calf.Mood==CalfMood.Listening)Purse+=5;
        calf.Notes=0;calf.Mood=CalfMood.Following;calf.Nerve=100;calf.Hush=2;
        calf.Wake.Clear();calf.LastTurn=Ship.Position;calf.Wake.Enqueue(Ship.Position);
        Say($"{calf.Name} knows the tune. Leave a clear wake to the nursery.");
    }
    public void Call()
    {
        if(Won||Lost||Ship.Mode!=VoyageMode.Sailing||Voice>0)return;
        Voice=4;
        var near=Herd.Where(c=>c.Mood==CalfMood.Following && Vector2.Distance(c.Position,Ship.Position)<760).ToArray();
        foreach(var calf in near){calf.Nerve=Math.Min(100,calf.Nerve+30);calf.Hush=3;}
        Say(near.Length>0?"The bell sounds low over the water. The calves keep to your wake.":"The bell carries. Bring it close to a following calf to steady it.");
    }
    public void Tend()
    {
        if(Won||Lost||Ship.Mode!=VoyageMode.Sailing||CastTime>0)return;
        CastTime=.7f;
        if(Home==Herd.Length && Vector2.Distance(Ship.Position,Nursery)<390){Won=true;Purse+=12;return;}
        for(int i=0;i<Grass.Length;i++)if(!cut[i] && Vector2.Distance(Ship.Position,Grass[i])<300)
        {cut[i]=true;Kelp+=2;Purse+=2;Say("Two green bundles come over the rail.");return;}
        var calf=Herd.Where(c=>c.Mood==CalfMood.Following && Vector2.Distance(c.Position,Ship.Position)<480)
            .MinBy(c=>c.Spirit+c.Nerve);
        if(calf!=null && Kelp>0){Kelp--;calf.Nerve=100;calf.Spirit=Math.Min(100,calf.Spirit+40);Say($"{calf.Name} takes the kelp straight from Vara’s hand.");return;}
        Say("Gather kelp at a green bed, or feed a calf alongside. Hail the tender when all are home.");
    }
    public void Patch()
    {
        if(Kits<=0||Ship.Mode!=VoyageMode.Sailing||Ship.Health>=Ship.MaxHealth)return;
        Kits--;Ship.Patch(outfit==Loadout.Lifeboat?55:36);Say("The crew stops the leak alongside the nursery well.");
    }
    public void Tick(float dt,SailInput helm)
    {
        if(Won||Lost||Ship.Mode!=VoyageMode.Sailing)return;
        Time+=dt;Voice=Math.Max(0,Voice-dt);CastTime=Math.Max(0,CastTime-dt);Speech=Math.Max(0,Speech-dt);
        var before=Ship.Position;Ship.Tick(dt,helm);sailed+=Vector2.Distance(before,Ship.Position);patrol+=dt;
        if(sailed>1100 && patrol>8 && Ship.Enemies.Count<3+Order.Tier/6)
        {
            sailed=patrol=0;EnemyKind[] species=[EnemyKind.Crab,EnemyKind.Ray,EnemyKind.Serpent,EnemyKind.Puffer];
            Ship.Spawn(species[(wave+Order.Tier)%4]);wave++;
        }
        foreach(var calf in Herd)
        {
            if(calf.Mood!=CalfMood.Following)continue;
            float gap=Vector2.Distance(calf.Position,Ship.Position);
            if(Vector2.Distance(calf.LastTurn,Ship.Position)>68)
            {calf.LastTurn=Ship.Position;calf.Wake.Enqueue(calf.LastTurn);}
            while(calf.Wake.Count>1 && Vector2.Distance(calf.Position,calf.Wake.Peek())<65)calf.Wake.Dequeue();
            var target=calf.Wake.Count>0?calf.Wake.Peek():Ship.Position;
            if(Vector2.Distance(Ship.Position,Nursery)<355 && gap<360)target=Nursery;
            var delta=target-calf.Position;
            if(delta.Length()>11 && (gap>135 || target==Nursery))
            {
                var bow=Vector2.Normalize(delta);
                float speed=(gap>350?146:100)*(calf.Hush>0?1.12f:1);
                calf.Position=Ship.World.Slide(calf.Position,calf.Position+bow*Math.Min(delta.Length(),speed*dt),23);
                calf.Bow=bow;
            }
            if(Vector2.Distance(calf.Position,Nursery)<230)
            {
                calf.Mood=CalfMood.Home;Purse+=9;
                Say(Home==Herd.Length?"The nursery has counted every calf. Come alongside and hail with E.":$"{calf.Name} joins the nursery. The other calls are still out there.");
                continue;
            }
            calf.Hit=Math.Max(0,calf.Hit-dt);calf.Hush=Math.Max(0,calf.Hush-dt);
            var enemy=Ship.Enemies.Where(e=>e.Health>0).MinBy(e=>Vector2.DistanceSquared(calf.Position,e.Position));
            float danger=enemy==null?float.MaxValue:Vector2.Distance(calf.Position,enemy.Position);
            calf.Nerve=Math.Clamp(calf.Nerve+dt*(gap>780?-3.8f:danger<335 && calf.Hush<=0?-1.8f:.85f),0,100);
            if(danger<100 && calf.Hit==0){calf.Hit=2.8f;calf.Spirit=Math.Max(0,calf.Spirit-7);calf.Nerve=Math.Max(0,calf.Nerve-5);}
            if(calf.Nerve==0){calf.Mood=CalfMood.Grazing;calf.Wake.Clear();Say($"{calf.Name} has stopped following. Come back and play its call.");}
        }
        if(Ship.Kills>=payout+3){payout+=3;Purse+=2;}
    }
}
