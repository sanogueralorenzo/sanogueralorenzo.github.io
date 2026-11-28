using BoatsNBeasts.Core;
using Godot;
using V2=System.Numerics.Vector2;

namespace BoatsNBeasts;

internal partial class TidePilot : Control
{
    internal MigrationWatch Trip=null!;
    ReefDrive D=>Trip.Drive;
    static readonly Font Title=new SystemFont{FontNames=["Baskerville","Georgia","serif"]};
    static readonly Color Ink=new("183c4a"),Paper=new("eadab5"),Gold=new("f5c896"),Pale=new("fff0cb"),Kelp=new("4c8164"),
        Rust=new("9c4e3c"),Wave=new("79a596"),Seafoam=new("a0dcc4");
    Rect2 ChartRect=>new(30,117,Size.X*.61f,Size.Y-225);
    Rect2 SetSail=>new(Size.X*.675f,Size.Y-141,Size.X*.285f,51);
    (V2 Mid,float Scale) ChartView()
    {
        var lo=D.Ship.Position;var hi=lo;
        for(int i=0;i<Trip.Total;i++){var point=Trip.Mark(i).Position;lo=V2.Min(lo,point);hi=V2.Max(hi,point);}
        return ((hi+lo)*.5f,Math.Min((ChartRect.Size.X-150)/(hi.X-lo.X+10),(ChartRect.Size.Y-105)/(hi.Y-lo.Y+10)));
    }
    Vector2 Point(V2 v){var (center,scale)=ChartView();return ChartRect.GetCenter()+new Vector2(v.X-center.X,v.Y-center.Y)*scale;}
    void Word(Vector2 p,string s,int px,Color color,bool serif=false)=>DrawString(serif?Title:ThemeDB.FallbackFont,p,s,fontSize:px,modulate:color);
    void Plate(Rect2 r){DrawRect(r,new Color(Ink,.97f));DrawLine(r.Position,r.Position+new Vector2(r.Size.X,0),Gold,2);}
    public override void _Draw()
    {
        if(Trip==null)return;
        if(Trip.Chart)Chart();else Helm();
        if(D.Lost||D.Won||D.Ship.Mode==VoyageMode.Upgrade)Result();
    }
    void Chart()
    {
        DrawRect(new(Vector2.Zero,Size),Ink);
        Word(new(32,48),Trip.Order.Island,34,Pale,true);
        Word(new(33,83),"NURSERY WATCH     /     "+Trip.Order.Region.ToUpperInvariant(),16,Seafoam);
        DrawRect(ChartRect,Paper);
        var view=ChartView();
        foreach(var place in D.Ship.World.Places.Where(OceanWorld.IsSolid))
        {
            var pos=Point(place.Position);
            if(ChartRect.Grow(-14).HasPoint(pos))DrawCircle(pos,Math.Clamp(place.Radius*view.Scale,2,16),new("b7b995"));
        }
        var boat=Point(D.Ship.Position);
        if(ChartRect.Grow(-30).HasPoint(boat))Word(boat+new Vector2(12,9),"Cutter",17,Rust,true);
        WaveMark(ChartRect.Position+new Vector2(42,42));Word(ChartRect.Position+new Vector2(22,92),"N ↑",17,Ink,true);
        for(int i=0;i<Trip.Total;i++)
        {
            var(pt,name)=Trip.Mark(i);var pos=Point(pt);
            if(i> D.Herd.Length && D.Cut(i-D.Herd.Length-1))continue;
            bool herd=i<D.Herd.Length, mother=i==D.Herd.Length;
            if(herd && D.Herd[i].Mood==CalfMood.Home)continue;
            if(i==Trip.Target){DrawDashedLine(Point(D.Ship.Position),pos,Rust,1.5f,7);DrawCircle(pos,18,Rust,false,2,true);}
            if(herd||mother)
            {
                DrawCircle(pos,mother?11:7,mother?Rust:Ink);
                DrawArc(pos+new Vector2(0,4),mother?17:11,0,Mathf.Pi,18,Wave,2,true);
            }
            else{DrawLine(pos+new Vector2(-5,-7),pos+new Vector2(0,6),Kelp,3);DrawLine(pos+new Vector2(5,-8),pos+new Vector2(0,6),Kelp,3);}
            if(herd||mother||i==Trip.Target)Word(pos+new Vector2(-23,-15),name,17,Ink,true);
        }
        var ship=Point(D.Ship.Position);
        DrawColoredPolygon([ship+new Vector2(0,-8),ship+new Vector2(6,6),ship+new Vector2(-6,6)],Rust);
        var p=new Vector2(Size.X*.675f,149);int width=(int)(Size.X-p.X-32);
        Word(p,"Shepherd the calves",30,Gold,true);
        DrawMultilineString(ThemeDB.FallbackFont,p+new Vector2(0,48),
            "Sail alongside a calf and answer its song with 1, 2 and 3. Guide it in your wake to the nursery mother. You can bring the calves in together or one at a time.",
            HorizontalAlignment.Left,width,21,modulate:Pale);
        DrawMultilineString(ThemeDB.FallbackFont,p+new Vector2(0,254),
            "Q steadies a following calf. E gathers kelp at green beds and feeds it to a calf alongside. Return to the mother and press E after the last arrival.",
            HorizontalAlignment.Left,width,19,modulate:Seafoam);
        DrawRect(SetSail,Gold);Word(SetSail.Position+new Vector2(15,33),"M    Take the helm",21,Ink);
        Word(new(32,Size.Y-48),$"Course    {Trip.Mark(Trip.Target).Name}     ·     Click a mark or Tab to cycle     ·     {D.Home}/{D.Herd.Length} home",18,Pale);
    }
    void WaveMark(Vector2 p)
    {
        for(int i=0;i<3;i++)DrawArc(p+new Vector2(i*12,0),7,.18f,Mathf.Pi-.18f,12,Wave,2,true);
    }
    void Helm()
    {
        Plate(new(21,18,385,95));Word(new(35,47),"THE WALKING TIDE    /    NURSERY WATCH",15,Gold);
        Word(new(35,86),$"{D.Home} of {D.Herd.Length} calves home",29,Pale,true);
        var (target,name)=Trip.Mark(Trip.Target);int deg=PilotSoundings.Bearing(D.Ship.Position,target);
        string[] dir=["N","NE","E","SE","S","SW","W","NW"];
        int span=(int)MathF.Round(V2.Distance(D.Ship.Position,target)/100);
        var where=new Vector2(Size.X-403,18);Plate(new(where,new Vector2(382,73)));
        Word(where+new Vector2(13,28),name,20,Pale,true);
        Word(where+new Vector2(13,56),$"{dir[((deg+22)/45)%8]}    {deg:000}°     ·     {span} {(span==1?"cable":"cables")}     ·     Tab course",17,Seafoam);
        foreach(var calf in D.Herd)
        {
            var p=Trip.Ocean.ElevatedScreen(calf.Position,1.25f);
            if(new Rect2(20,118,Size.X-150,Size.Y-290).HasPoint(p) && calf.Mood!=CalfMood.Home)
                Word(p,calf.Mood==CalfMood.Following?$"{calf.Name}   {calf.Nerve:0}% calm · {calf.Spirit:0}% health":calf.Name,17,Pale,true);
        }
        if(D.Singer is {} c)
        {
            var pane=new Rect2(22,Size.Y-241,Math.Min(782,Size.X-44),69);Plate(pane);
            string notes=string.Join("    ",c.Song.Select((n,i)=>i<c.Notes?"✓":n switch {1=>"1 Low",2=>"2 Middle",_=>"3 High"}));
            Word(pane.Position+new Vector2(15,24),$"ANSWER {c.Name.ToUpperInvariant()}’S CALL",15,Gold);
            Word(pane.Position+new Vector2(15,53),notes,23,Pale,true);
        }
        if(D.Speech>0){var pane=new Rect2(22,Size.Y-158,Size.X-44,44);Plate(pane);Word(pane.Position+new Vector2(14,28),D.Report,18,Gold);}
        var bar=new Rect2(22,Size.Y-105,Size.X-44,83);Plate(bar);
        Word(bar.Position+new Vector2(14,30),$"Hull {D.Ship.Health:0}/{D.Ship.MaxHealth:0}    ·    {D.Kelp} kelp    ·    {D.Kits} patches    ·    {D.Purse} silver",20,Pale,true);
        Word(bar.Position+new Vector2(14,61),"WASD Helm    Shift Surge    Space Gun    1–3 Song    Q Soothe    E Tend / hail    R Patch    M Chart",17,Seafoam);
    }
    void Result()
    {
        DrawRect(new(Vector2.Zero,Size),new Color(Ink,.86f));
        var p=Size/2-new Vector2(310,133);Plate(new(p,new(620,266)));
        if(D.Ship.Mode==VoyageMode.Upgrade)
        {
            Word(p+new Vector2(20,46),"Refit the nursery cutter",30,Gold,true);
            var choices=D.Ship.UpgradeChoices;
            for(int i=0;i<Math.Max(choices.Count,1);i++)
                Word(p+new Vector2(23,94+i*42),choices.Count==0?"Enter   Restore hull":$"{i+1}    {Voyage.UpgradeNames[choices[i]]}",22,Pale);
        }
        else
        {
            Word(p+new Vector2(20,46),D.Won?"The nursery answers":"The herd slips away",30,Gold,true);
            Word(p+new Vector2(20,101),$"{D.Purse} silver aboard.",23,Pale);
            Word(p+new Vector2(20,197),"Enter or click to return to Last Light",20,Seafoam);
        }
    }
    public override void _GuiInput(InputEvent input)
    {
        if(input is not InputEventMouseButton{Pressed:true,ButtonIndex:MouseButton.Left} click)return;
        if(D.Won||D.Lost)Trip.Settle();
        else if(D.Ship.Mode==VoyageMode.Upgrade)
        {
            var p=Size/2-new Vector2(310,133);
            for(int i=0;i<Math.Max(1,D.Ship.UpgradeChoices.Count);i++)
                if(new Rect2(p+new Vector2(12,67+i*42),new(580,41)).HasPoint(click.Position))Trip.Refit(i);
        }
        else if(Trip.Chart && SetSail.HasPoint(click.Position))Trip.Fold();
        else if(Trip.Chart && ChartRect.HasPoint(click.Position))
        {
            int i=Enumerable.Range(0,Trip.Total).Where(k=>k<=D.Herd.Length || !D.Cut(k-D.Herd.Length-1)).MinBy(k=>Point(Trip.Mark(k).Position).DistanceSquaredTo(click.Position));
            Trip.Choose(i);
        }
        else return;
        AcceptEvent();
    }
}
