using Godot;
using BoatsNBeasts.Core;
using V2 = System.Numerics.Vector2;

namespace BoatsNBeasts;

internal partial class PilotPlot : Control
{
    internal PilotageVoyage Trip = null!;
    PilotSoundings Run=>Trip.Sights;
    static readonly Color Ink=new("183845"),Cream=new("fce8c2"),Paper=new("e4d3a6"),Teal=new("91dfcd"),
        Rust=new("944a34"),Land=new("769686"),Gold=new("efbf77");
    static readonly Font Heading=new SystemFont{FontNames=["Baskerville","Georgia","serif"]};
    Rect2 Map=>new(38,120,Size.X*.67f,Size.Y-224);
    Rect2 Sail=>new(Size.X*.71f,Size.Y-170,Size.X*.25f,56);
    Vector2 cursor;
    bool first=true,second=true,initialized;
    static Vector2 G(V2 v)=>new(v.X,v.Y);
    Vector2 Pixel(V2 world)=>Map.GetCenter()+G(world)*ScaleFactor;
    float ScaleFactor=>Math.Min(Map.Size.X/(PilotSoundings.Bounds.X*2.03f),Map.Size.Y/(PilotSoundings.Bounds.Y*2.03f));
    V2 World(Vector2 pixel) {var v=(pixel-Map.GetCenter())/ScaleFactor;return new(v.X,v.Y);}
    void Text(Vector2 p,string value,int size,Color color,bool serif=false) =>
        DrawString(serif?Heading:ThemeDB.FallbackFont,p,value,fontSize:size,modulate:color);
    void Plate(Rect2 r){DrawRect(r,new Color(Ink,.97f));DrawLine(r.Position,r.Position+new Vector2(r.Size.X,0),Gold,2);}
    void Paragraph(Vector2 at,string text,int width,int size,Color tone) =>
        DrawMultilineString(ThemeDB.FallbackFont,at,text,HorizontalAlignment.Left,width,size,modulate:tone);
    public override void _Draw()
    {
        if(Trip==null)return;
        if(Trip.ChartOpen)DrawChart();else DrawHelm();
        if(Run.Lost || Run.Won || Run.Ship.Mode==VoyageMode.Upgrade)DrawResult();
    }
    void DrawChart()
    {
        DrawRect(new(Vector2.Zero,Size),Ink);
        Text(new(38,53),Trip.Order.Island.Length>0?Trip.Order.Island:Trip.Order.Region,37,Cream,true);
        Text(new(40,88),$"PILOT BOOK     /     {Trip.Order.Region.ToUpperInvariant()}     /     {Run.Page} OF {Run.Fixes.Length} DEPTHS FILED",16,Teal);
        DrawRect(Map,Paper);
        for(int i=-6;i<=6;i++)
        {
            float x=Pixel(new(i*1000,0)).X;
            if(x>Map.Position.X&&x<Map.End.X)DrawLine(new(x,Map.Position.Y),new(x,Map.End.Y),new Color("c1b68e"),1);
        }
        for(int j=-5;j<=5;j++)
        {
            float y=Pixel(new(0,j*1000)).Y;
            if(y>Map.Position.Y&&y<Map.End.Y)DrawLine(new(Map.Position.X,y),new(Map.End.X,y),new Color("c1b68e"),1);
        }
        var north=Map.Position+new Vector2(43,52);
        DrawColoredPolygon([north+new Vector2(0,-19),north+new Vector2(6,5),north,north+new Vector2(-6,5)],Ink);
        Text(north+new Vector2(-7,-24),"N",16,Ink,true);
        float key=ScaleFactor*1000;
        var scale=Map.Position+new Vector2(22,Map.Size.Y-24);
        DrawLine(scale,scale+Vector2.Right*key,Ink,2);
        Text(scale+new Vector2(0,-7),"10 cables",15,Ink,true);
        foreach(var place in Run.Coast)
        {
            var p=Pixel(place.Position);
            if(Map.Grow(-12).HasPoint(p))DrawCircle(p,Math.Clamp(place.Radius*ScaleFactor,2,19),Land);
        }
        if(!Run.Surveyed)
        {
            Ray(Run.Fix.Near,Run.Fix.FirstBearing,first,Rust);
            Ray(Run.Fix.Far,Run.Fix.SecondBearing,second&&Run.SecondSight,new("366365"));
        }
        foreach(var light in Run.Lights)
        {
            var p=Pixel(light.Position);
            bool reader=!Run.Surveyed && light==Run.Lights[Run.Fix.Far];
            if(reader)DrawCircle(p,12,new("366365"),false,2,true);
            DrawCircle(p,7,Ink);
            Text(p+new Vector2(-30,-14),light.Name,16,Ink,true);
        }
        for(int i=0;i<Run.Page;i++)DrawCircle(Pixel(Run.Fixes[i].Position),4,new("568476"));
        var here=Pixel(Run.Ship.Position); Text(here+new Vector2(11,9),"Cutter",15,Rust,true);DrawColoredPolygon([here+new Vector2(0,-10),here+new Vector2(7,7),here,here+new Vector2(-7,7)],Rust);
        if(Run.Pin is { } pin) Pin(Pixel(pin));
        if(Run.Surveyed){var p=Pixel(Run.Landing);DrawCircle(p,13,Rust,false,3,true);Text(p+new Vector2(16,6),"Pilot tender",20,Ink,true);}
        var at=new Vector2(Size.X*.71f,142); int width=(int)(Size.X-at.X-40);
        Text(at,Run.Surveyed?"Make for the tender":"Cross bearings",29,Gold,true);
        if(!Run.Surveyed)
        {
            var fix=Run.Fix;
            Paragraph(at+new Vector2(0,48),$"1   From {Run.Lights[fix.Near].Name}, the pilot saw the channel at {fix.FirstBearing:000}°.",width,21,Cream);
            string report=Run.SecondSight?$"2   From {Run.Lights[fix.Far].Name}, the bearing is {fix.SecondBearing:000}°.":"2   Sail beside " +Run.Lights[fix.Far].Name+" and hail with Q to take the second bearing.";
            Paragraph(at+new Vector2(0,145),report,width,21,Cream);
            Paragraph(at+new Vector2(0,272),"Pin the meeting of the two lines. Sail to your pin and cast the lead with E. A correct fix charts a safe depth.",width,19,Teal);
        }
        else Paragraph(at+new Vector2(0,49),"All soundings agree. Sail to the tender marked on the chart and hail with Q to file the new approach.",width,21,Cream);
        DrawRect(Sail,Gold);Text(Sail.Position+new Vector2(18,36),"M   Return to the helm",22,Ink);
        Text(new(40,Size.Y-39),"Click the chart to pin a course   ·   Arrows move the plotter   ·   Enter pins   ·   1 / 2 toggle bearings",18,Cream);
        if(initialized)DrawArc(cursor,8,0,Mathf.Tau,30,Ink,1.5f,true);
    }
    void Ray(int index,int bearing,bool visible,Color color)
    {
        if(!visible)return;
        var start=Pixel(Run.Lights[index].Position);var v=G(PilotSoundings.Along(bearing));
        float t=float.PositiveInfinity;
        if(Mathf.Abs(v.X)>.001f)t=Mathf.Min(t,((v.X>0?Map.End.X:Map.Position.X)-start.X)/v.X);
        if(Mathf.Abs(v.Y)>.001f)t=Mathf.Min(t,((v.Y>0?Map.End.Y:Map.Position.Y)-start.Y)/v.Y);
        DrawDashedLine(start,start+v*t,color,1.8f,7);
    }
    void Pin(Vector2 p){DrawLine(p-new Vector2(7,7),p+new Vector2(7,7),Rust,3);DrawLine(p+new Vector2(-7,7),p+new Vector2(7,-7),Rust,3);}
    internal bool ChartKey(Key key)
    {
        if(!initialized){initialized=true;cursor=Pixel(Run.Ship.Position);}
        switch(key)
        {
            case Key.Left: cursor.X-=9;break;case Key.Right:cursor.X+=9;break;
            case Key.Up:cursor.Y-=9;break;case Key.Down:cursor.Y+=9;break;
            case Key.Enter:Run.Pin=World(cursor);break;
            case Key.Key1:first=!first;break;case Key.Key2:second=!second;break;
            default:return false;
        }
        cursor=cursor.Clamp(Map.Position+Vector2.One*8,Map.End-Vector2.One*8);QueueRedraw();return true;
    }
    public override void _GuiInput(InputEvent e)
    {
        if(e is not InputEventMouseButton{Pressed:true,ButtonIndex:MouseButton.Left} click)return;
        if(Run.Lost||Run.Won){Trip.Settle();return;}
        if(Run.Ship.Mode==VoyageMode.Upgrade)
        {
            var options=Run.Ship.UpgradeChoices;
            var origin=Size*.5f-new Vector2(288,82);
            for(int i=0;i<Math.Max(1,options.Count);i++)
                if(new Rect2(origin+new Vector2(-6,23+i*36),new(550,36)).HasPoint(click.Position))
                {
                    if(options.Count==0)Run.Ship.TakeUpgradeHeal();else Run.Ship.Upgrade(options[i]);
                    break;
                }
            AcceptEvent();return;
        }
        if(!Trip.ChartOpen)return;
        if(Map.HasPoint(click.Position)){cursor=click.Position;initialized=true;Run.Pin=World(cursor);QueueRedraw();}
        else if(Sail.HasPoint(click.Position))Trip.ResumeSailing();
        AcceptEvent();
    }
    void DrawHelm()
    {
        Plate(new(24,20,450,89));
        Text(new(40,49),$"{Trip.Order.Region.ToUpperInvariant()}    /    PILOTAGE",16,Gold);
        Text(new(40,86),$"{Run.Page} of {Run.Fixes.Length} depths filed",28,Cream,true);
        foreach(var light in Run.Lights)
        {
            var p=Trip.Ocean.ElevatedScreen(light.Position,1.3f);
            if(new Rect2(20,115,Size.X-135,Size.Y-245).HasPoint(p))Text(p,light.Name,18,Cream,true);
        }
        V2? target=Run.Surveyed?Run.Landing:Run.Pin;
        string course=target is { } mark ? $"{(Run.Surveyed?"TENDER":"YOUR PIN")}    {PilotSoundings.Bearing(Run.Ship.Position,mark):000}°    ·    {V2.Distance(Run.Ship.Position,mark)/100:0} cables"
            : $"SECOND LIGHT    {Run.Lights[Run.Fix.Far].Name}    ·    open M to plot";
        Plate(new(Size.X-500,20,475,55));Text(new(Size.X-482,54),course,19,Teal);
        Plate(new(24,Size.Y-90,Size.X-48,63));
        Text(new(39,Size.Y-51),$"Hull {Run.Ship.Health:0}/{Run.Ship.MaxHealth:0}     {Run.Silver} silver     ·     WASD Helm   Shift Surge   Space Gun   Q Hail / hook   E Sound   R Patch ×{Run.Kits}   M Chart",17,Cream);
        if(Run.ReportLeft>0){Plate(new(24,Size.Y-152,Size.X-48,48));Text(new(41,Size.Y-122),Run.Report,18,Gold);}
    }
    void DrawResult()
    {
        DrawRect(new(Vector2.Zero,Size),new Color(Ink,.83f));var r=new Rect2(Size*.5f-new Vector2(310,130),new(620,260));
        Plate(r);var at=r.Position+new Vector2(22,48);
        if(Run.Ship.Mode==VoyageMode.Upgrade)
        {
            Text(at,"Refit the survey cutter",30,Cream,true);
            for(int i=0;i<Run.Ship.UpgradeChoices.Count;i++){int choice=Run.Ship.UpgradeChoices[i];Text(at+new Vector2(0,49+i*36),$"{i+1}    {Voyage.UpgradeNames[choice]}",21,Teal);}
            if(Run.Ship.UpgradeChoices.Count==0)Text(at+new Vector2(0,52),"Enter   ·   Restore hull",21,Teal);
        }
        else
        {
            Text(at,Run.Won?"The pilots accept your chart":"Lost on the sounding grounds",30,Cream,true);
            Text(at+new Vector2(0,54),$"{Run.Silver} silver in the survey purse.",22,Gold);
            Text(at+new Vector2(0,145),"Enter or click to return to Last Light",20,Teal);
        }
    }
}
