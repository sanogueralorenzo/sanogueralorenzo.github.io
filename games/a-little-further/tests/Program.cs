using Further.Core;
using System.Numerics;
var tuning=new CombatTuning(new(17.6f,.75f,.5f,1,2),new(7,1.4f,1.1f,6,.4f),new(14,1.1f,.3f,1,1),new(12,2.4f,1,1,1),new(22,9,2.64f),new(45,17.6f,1.8f),new(14.4f,.92f,0,1,.5f),new(7.2f,1.25f,0,0,.5f));
int checks=0;void Check(bool b,string message){checks++;if(!b)throw new Exception(message);}
if(args.Contains("--survey"))
{
 var report=new List<object>();
 foreach(int seed in new[]{1,1701,73919,2147483647})
 foreach(var cell in new[]{new Cell(0,0),new Cell(1,0),new Cell(0,1),new Cell(-1,-1)})
 {
  var world=new World(seed);var island=world.IslandAt(cell);int area=0;float high=0;
  for(float z=-180;z<180;z+=2)for(float x=-180;x<180;x+=2){float h=World.Height(island,island.Center+new Vector2(x,z));if(h>0){area+=4;high=MathF.Max(high,h);}}
  report.Add(new{seed,cell,radius=island.Radius,landAreaM2=area,highest=high,scenery=IslandLayout.Scenery(island).Count});
 }
 Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(report,new System.Text.Json.JsonSerializerOptions{WriteIndented=true}));return;
}
// Coast-derived anchor points must stay on land, including the third landing that
// exposed a below-water spawn in the native run. Check both directions of its jetty.
foreach(int seed in Enumerable.Range(1,128).Append(1701).Append(73919))
foreach(var cell in new[]{new Cell(0,0),new Cell(1,0),new Cell(1,1),new Cell(-1,-1)})
{
 var world=new World(seed);var island=world.IslandAt(cell);
 Check(World.Height(island,island.Landing)>.5f,"submerged landing");
 Check(World.Height(island,island.Landing-new Vector2(0,10))<-.3f,"boat approach is on land");
 Check(World.Height(island,island.Landing+new Vector2(0,2))>0,"landing has no inland exit");
}
foreach(int seed in new[]{1701,73919})foreach(var cell in new[]{new Cell(0,0),new Cell(1,0),new Cell(1,1),new Cell(-1,-1)})
{
 var run=new Run(seed,tuning);run.World.Origin=cell;var island=run.World.IslandAt(cell);
 run.Ship.Position=island.Landing-new Vector2(0,10);run.Position=run.Ship.Position;run.Tick(1f/60,new(Vector2.Zero,Interact:true));
 for(int coin=0;coin<8;coin++)
 {
  int tick=0;for(;tick<600 && Vector2.Distance(run.Position,run.TreasureAt(coin))>1.7f;tick++)
  {
   var d=Vector2.Normalize(run.TreasureAt(coin)-run.Position);run.Tick(1f/60,new(d,Jump:tick%120==0,HoldJump:true));
  }
  Check(tick<600,$"blocked trail seed {seed}, cell {cell}, coin {coin}, position {run.Position}");
 }
 Check(run.Treasure.Count>=8,"trail did not award treasure");
}
foreach(int seed in new[]{1,1701,73919,Int32.MaxValue})
{
 var island=new World(seed).IslandAt(new(1,1));var data=TerrainMeshData.Generate(island,true);
 Check(data.Indices.All(i=>i>=0&&i<data.Positions.Length),"terrain index outside vertices");
 Check(data.Normals.All(n=>float.IsFinite(n.X)&&MathF.Abs(n.Length()-1)<.001f&&n.Y>0),"invalid terrain normal");
 Check(data.Positions.All(p=>MathF.Abs(p.Y-World.Height(island,island.Center+new Vector2(p.X,p.Z)))<.001f),"mesh and traversal disagree");
 Check(data.Scenery.Count<1109 && data.Meadow.Count<20000,"unbounded scenery");
}
var helm=PrivateSources.AvoidShore(new Ship(),1,1,_=>2);Check(helm.Steer==1,"shore assistance canceled full helm");
{
 var run=new Run(1701,tuning);run.Ship.Position=new(0,-137);run.Position=run.Ship.Position;
 var target=new Vector2(0,-180);
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
// Exercise cross-role benefits through actual combat ticks, outside captain range.
Run Encounter(params Role[] roles)
{
 var r=new Run(1701,tuning);r.Ship.Position=r.Nearest.Landing-new Vector2(0,10);r.Position=r.Ship.Position;r.Tick(1f/60,new(Vector2.Zero,Interact:true));
 r.Position=r.Current!.Shrine;r.Height=r.World.Height(r.Position);r.Crew.Clear();foreach(var role in roles)r.Crew.Add(new(role));return r;
}
float FirstShot(Role role,bool marked=false,bool chilled=false)
{
 var r=Encounter(role);var foe=new Foe(1,r.Position+new Vector2(8,0),0,500){Marked=marked,Chilled=chilled?2:0};r.Enemies.Add(foe);r.Tick(1f/60,new());return 500-foe.Hp;
}
Check(FirstShot(Role.Gunner,true)>FirstShot(Role.Gunner)*1.5f,"marks do not strengthen gunner");
Check(FirstShot(Role.Harpooner,chilled:true)>FirstShot(Role.Harpooner)*2,"chill does not enable shatter");
{
 var r=Encounter(Role.Stormcaller,Role.Gunner);var p=r.Position+new Vector2(8,0);r.Enemies.Add(new(1,p,0,19));r.Enemies.Add(new(2,p+new Vector2(2,0),0,200));
 r.Tick(1f/60,new());Check(r.Kills>0 && r.Enemies.Any(e=>e.Marked&&e.Hp<180),"storm/gunner chain failed");
}
foreach(int seed in new[]{1,1701,73919,Int32.MaxValue})
{
    var world=new World(seed);foreach(var c in world.Visible(Vector2.Zero))
    {
        var i=world.IslandAt(c);Check(i==world.IslandAt(c),"generation changed");
        for(int z=-160;z<160;z+=3)for(int x=-160;x<160;x+=3)Check(float.IsFinite(World.Height(i,i.Center+new Vector2(x,z))),"nonfinite height");
    }
    Check(world.Visible(Vector2.Zero).Count()==9,"stream bounds");
    var run=new Run(seed,tuning);run.Ship.Position=run.Nearest.Landing-new Vector2(0,8);run.Position=run.Ship.Position;
    run.Tick(1f/60,new(Vector2.Zero,Interact:true));Check(run.Mode==RunMode.Exploring,"landing inaccessible");
    for(int tick=0;tick<4800 && Vector2.Distance(run.Position,run.Current!.Shrine)>2.8f;tick++)
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
 var r=new Run(1701,tuning);r.Ship.Heading=MathF.PI/2;r.Ship.Position=new(0,-190);r.Position=r.Ship.Position;
 for(int t=0;t<60*1300;t++)r.Tick(1f/60,new(new(0,1),Boost:true));
 Check(r.ShiftCount>=8,"long travel did not rebase "+r.ShiftCount);Check(r.Position.Length()<2600,"unbounded local position");Check(r.World.Visible(r.Position).Count()==9,"stream grew");
 Console.WriteLine($"Extended travel: {r.ShiftCount} rebases, origin {r.World.Origin}, local {r.Position}");
}
{
 var r=new Run(2,tuning);r.Crew.Clear();foreach(var role in Enum.GetValues<Role>().Take(4))r.Crew.Add(new(role));
 r.Mode=RunMode.Choosing;r.Offers=[Role.Cook];r.Choose(0);Check(r.Crew.Count==4&&r.Crew[2].Level==2,"crew cap/development");
 r.Mode=RunMode.Choosing;r.Offers=[Role.Harpooner];r.Choose(0,1);Check(r.Crew.Count==4 && r.Crew[1].Role==Role.Harpooner,"replacement failed");
 r.Mode=RunMode.Sailing;r.Ship.Position=r.Nearest.Landing-new Vector2(0,8);r.Position=r.Ship.Position;r.Tick(1f/60,new(Vector2.Zero,Interact:true));r.Position=r.Current!.Shrine;r.Height=r.World.Height(r.Position);r.Crew.Clear();
 r.Enemies.Add(new(1,r.Position,1,100000));
 for(int i=0;i<3000&&r.Mode!=RunMode.Dead;i++)r.Tick(1f/60,new());
 Check(r.Mode==RunMode.Dead,"death absent");double ended=r.Time;r.Tick(1,new(new(1,1)));Check(r.Time==ended,"dead simulation advanced");
 var fresh=new Run(3,tuning);Check(fresh.Gold==0&&fresh.Claimed.Count==0&&fresh.Health==100&&fresh.Crew.Count==1,"death leaked state");
}
Console.WriteLine($"PASS {checks} checks; four seeds, exploration, combat, reward, death and long travel.");
