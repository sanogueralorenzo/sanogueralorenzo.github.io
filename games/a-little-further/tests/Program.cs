using Further.Core;
using System.Numerics;
var tuning=new CombatTuning(new(17.6f,.75f,.5f,1,2),new(7,1.4f,1.1f,6,.4f),new(14,1.1f,.3f,1,1),new(12,2.4f,1,1,1),new(22,9,2.64f),new(45,17.6f,1.8f),new(14.4f,.92f,0,1,.5f),new(7.2f,1.25f,0,0,.5f));
int checks=0;void Check(bool b,string message){checks++;if(!b)throw new Exception(message);}
var helm=PrivateSources.AvoidShore(new Ship(),1,1,_=>2);Check(helm.Steer==1,"shore assistance canceled full helm");
{
 var run=new Run(1701,tuning);run.Ship.Position=new(0,-60);run.Position=run.Ship.Position;
 var target=new Vector2(0,-95);
 for(int tick=0;tick<60*45 && Vector2.Distance(run.Position,target)>12;tick++)
 {
  var d=target-run.Position;float desired=MathF.Atan2(d.X,d.Y),error=MathF.Atan2(MathF.Sin(desired-run.Ship.Heading),MathF.Cos(desired-run.Ship.Heading));
  run.Tick(1f/60,new(new(Math.Clamp(-error*2,-1,1),MathF.Abs(error)>1?0:1)));
 }
 Check(Vector2.Distance(run.Position,target)<12,"boat could not turn away from shore");
}
{
 var random=new Random(61);
 for(int sample=0;sample<100;sample++)
 {
  var foes=Enumerable.Range(0,30).Select(i=>new Foe(i,new(random.Next(-20,21),random.Next(-20,21)),0,i%4==0?0:20)).ToArray();
  var expected=foes.Where(e=>e.Hp>0 && e.Position.LengthSquared()<225).MinBy(e=>e.Position.LengthSquared());
  Check(ReferenceEquals(expected,PrivateSources.ClosestEnemy(foes,Vector2.Zero,15)),"recovered nearest-target selection changed eligibility or ties");
 }
}
foreach(int seed in new[]{1,1701,73919,Int32.MaxValue})
{
    var world=new World(seed);foreach(var c in world.Visible(Vector2.Zero))
    {
        var i=world.IslandAt(c);Check(i==world.IslandAt(c),"generation changed");
        for(int z=-60;z<60;z+=3)for(int x=-60;x<60;x+=3)Check(float.IsFinite(World.Height(i,i.Center+new Vector2(x,z))),"nonfinite height");
    }
    Check(world.Visible(Vector2.Zero).Count()==25,"stream bounds");
    var run=new Run(seed,tuning);run.Ship.Position=run.Nearest.Landing-new Vector2(0,8);run.Position=run.Ship.Position;
    run.Tick(1f/60,new(Vector2.Zero,Interact:true));Check(run.Mode==RunMode.Exploring,"landing inaccessible");
    for(int tick=0;tick<1200 && Vector2.Distance(run.Position,run.Current!.Shrine)>2.8f;tick++)
    {
        var direction=Vector2.Normalize(run.Current!.Shrine-run.Position);
        run.Tick(1f/60,new(direction,Jump:tick%50==0,HoldJump:true));
    }
    Check(Vector2.Distance(run.Position,run.Current!.Shrine)<3,"summit unreachable seed "+seed);
    run.Tick(1f/60,new(Vector2.Zero,Interact:true));
    for(int tick=0;tick<1600 && run.Mode==RunMode.Exploring;tick++)
    {
        float a=tick*.008f;var target=run.Current.Shrine+new Vector2(MathF.Sin(a),MathF.Cos(a))*5;
        run.Tick(1f/60,new(Vector2.Normalize(target-run.Position),Dodge:run.DodgeCooldown<=0));
    }
    Check(run.Mode==RunMode.Choosing,"shrine never rewarded seed "+seed);
    Check(run.Kills>0,"auto attacks failed");run.Choose(0);Check(run.Mode==RunMode.Exploring,"choice did not resume");
}
{
 var r=new Run(1701,tuning);r.Ship.Heading=MathF.PI/2;r.Ship.Position=new(0,-82);r.Position=r.Ship.Position;
 for(int t=0;t<60*1300;t++)r.Tick(1f/60,new(new(0,1),Boost:true));
 Check(r.ShiftCount>=20,"long travel did not rebase "+r.ShiftCount);Check(r.Position.Length()<1000,"unbounded local position");Check(r.World.Visible(r.Position).Count()==25,"stream grew");
 Console.WriteLine($"Extended travel: {r.ShiftCount} rebases, origin {r.World.Origin}, local {r.Position}");
}
{
 var r=new Run(2,tuning);r.Crew.Clear();foreach(var role in Enum.GetValues<Role>().Take(4))r.Crew.Add(new(role));
 r.Mode=RunMode.Choosing;r.Offers=[Role.Cook];r.Choose(0);Check(r.Crew.Count==4&&r.Crew[2].Level==2,"crew cap/development");
 r.Mode=RunMode.Choosing;r.Offers=[Role.Harpooner];r.Choose(0,1);Check(r.Crew.Count==4 && r.Crew[1].Role==Role.Harpooner,"replacement failed");
 r.Mode=RunMode.Exploring;r.Current=r.Nearest;r.Position=r.Current.Shrine;r.Height=r.World.Height(r.Position);r.Crew.Clear();
 r.Enemies.Add(new(1,r.Position,1,100000));
 for(int i=0;i<3000&&r.Mode!=RunMode.Dead;i++)r.Tick(1f/60,new());
 Check(r.Mode==RunMode.Dead,"death absent");double ended=r.Time;r.Tick(1,new(new(1,1)));Check(r.Time==ended,"dead simulation advanced");
 var fresh=new Run(3,tuning);Check(fresh.Gold==0&&fresh.Claimed.Count==0&&fresh.Health==100&&fresh.Crew.Count==1,"death leaked state");
}
Console.WriteLine($"PASS {checks} checks; four seeds, exploration, combat, reward, death and long travel.");
