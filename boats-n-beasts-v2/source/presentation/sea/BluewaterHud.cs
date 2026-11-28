using BoatsNBeasts.Core;
using Godot;
using V2 = System.Numerics.Vector2;

namespace BoatsNBeasts;

internal partial class BluewaterHud : Control
{
    public BluewaterVoyage Scene = null!;
    BluewaterCourse Course => Scene.Course;
    readonly Font text = ThemeDB.FallbackFont;
    readonly Font serif = new SystemFont {FontNames=["Baskerville","Georgia"]};
    static readonly Color Ink=new("132c3a"), Cream=new("ffedc9"), Mint=new("8fe2c8"), Red=new("ff7a57");
    Vector2 S(V2 p,float h=0)=>Scene.Sea.ElevatedScreen(p,h);
    void Box(float x,float y,float w,float h,Color edge)
    {
        DrawRect(new(x,y,w,h),new Color(Ink,.94f));
        DrawLine(new(x,y),new(x+w,y),edge,2);
    }
    void Text(string value,float x,float y,int px,Color color,bool title=false)
        =>DrawString(title?serif:text,new(x,y),value,HorizontalAlignment.Left,-1,px,color);
    public override void _Draw()
    {
        if(Scene.InMenu)return;
        var c=Course;var ship=c.Ship;Color brass=new(c.Country.Accent);
        var target=c.Destination;
        var goal=S(target,1.05f);
        if(c.HasMarks)
            for(int i=0;i<3;i++)
            {
                var p=S(c.Mark(i),.10f);
                if(!new Rect2(Vector2.Zero,Size).HasPoint(p))continue;
                var tint=i==c.RequiredMark?brass:Mint;
                DrawPolyline(Ring(c.Mark(i),37),tint,2,true);
                if(i==1)DrawArc(p,12,0,Mathf.Tau,22,tint,4,true);
                else
                {
                    DrawPolyline([p+new Vector2(-12,-8),p+Vector2.Down*8,p+new Vector2(12,-8)],tint,4,true);
                    if(i==2)DrawLine(p+Vector2.Down*8,p+Vector2.Up*14,tint,4,true);
                }
            }
        if(!c.WeatherRead && c.Weather.Marked && c.Phase is ChartPhase.Running or ChartPhase.Boss) Weather(brass);
        if(c.Phase==ChartPhase.Running)
        {
            var point=GetViewport().GetMousePosition();
            foreach(var bank in c.Banks)
            {
                if(!bank.Breakable||bank.Broken||V2.DistanceSquared(ship.Position,bank.Shackle)>600*600)continue;
                var clasp=S(bank.Shackle,.28f);
                DrawArc(clasp,7,0,Mathf.Tau,14,new Color("ffd289"),1.8f,true);
                if(clasp.DistanceSquaredTo(point)<46*46)
                    Text(bank.Hits>0?"Shackle  ·  One hit left":"Shackle  ·  Two shots",clasp.X+12,clasp.Y,15,Cream);
            }
        }
        foreach(var foe in ship.Enemies)
        {
            if(foe.Role==PatrolRole.Pursuit||foe.Health<=0)continue;
            var pin=S(foe.Position,.76f);
            if(!new Rect2(Vector2.Zero,Size).HasPoint(pin))continue;
            Color tint=foe.Role==PatrolRole.Caller?Mint:foe.Role==PatrolRole.Mortar?Red:Cream;
            DrawColoredPolygon([pin+new Vector2(-6,-4),pin+new Vector2(6,-4),pin+new Vector2(0,5)],tint);
        }
        if(c.Phase==ChartPhase.Boss && c.Tell>0) CommanderTell();
        var bow=new V2(MathF.Sin(ship.Heading),-MathF.Cos(ship.Heading));
        var deckhand=S(ship.Position-new V2(-bow.Y,bow.X)*31-bow*9,.67f);
        if(c.Tether!=null)
        {
            var point=S(c.Tether.Position,.35f);
            BoardingLine.Draw(this,deckhand,point,c.SeamReady?.05f:.45f,c.SeamReady);
            if(c.SeamReady)
            {
                DrawArc(point,17,0,Mathf.Tau,24,brass,3,true);
                DrawLine(point-Vector2.Right*22,point+Vector2.Right*22,Cream,2,true);
            }
        }
        else if(c.HookTime>0)BoardingLine.Draw(this,deckhand,S(c.HookEnd,.35f),c.HookTime/.55f,false);
        var previous=ship.Position;
        foreach(var lighter in c.Fleet)
        {
            var d=OceanWorld.Unit(previous-lighter.Position);
            DrawLine(S(previous-d*77,.18f),S(lighter.Position+d*73,.16f),new Color(brass,.85f),2,true);
            var p=S(lighter.Position,.88f);
            DrawRect(new(p.X-19,p.Y-1,38,4),Ink);
            DrawRect(new(p.X-19,p.Y-1,38*Math.Clamp(lighter.Health/lighter.Maximum,0,1),4),Mint);
            previous=lighter.Position;
        }
        float w=Size.X,h=Size.Y;
        string name=c.Crossing ? c.RedPassage ? c.PrizeName : "Sheltered gate" : c.JobName;
        if(c.Field!=0 && c.Tender is {Health:>0} aid)
        {
            var p=S(aid.Position,1.12f);
            string label=c.Field==2?$"R  ·  {(c.LooseFormation?"On the beam":"Close astern")}  {aid.Health:0}%":c.Field==3 ? $"Q  ·  {c.Squadron!.Signal}" : c.SupportName;
            DrawPolyline(Ring(aid.Position,100),Mint,2,true);
            if(new Rect2(new(30,115),Size-new Vector2(60,330)).HasPoint(p))
            {
                float tw=text.GetStringSize(label,fontSize:15).X+20;
                Box(p.X-tw/2,p.Y-18,tw,25,Mint);Text(label,p.X-tw/2+10,p.Y,15,Mint);
            }
            if(c.Field==1 && c.Picket is {Health:>0} picket)
            {
                var foe=S(picket.Position,1.05f);
                if(new Rect2(new(20,115),Size-new Vector2(40,320)).HasPoint(foe))
                    Text(picket.Health<picket.MaxHealth*.70f?"Q  ·  Board prize":"Picket under way",foe.X-55,foe.Y-12,15,Red);
            }
            if(c.Field==3 && c.FlagshipHull>0)DrawPolyline(Ring(c.Battery,90),Red,3,true);
        }
        if(c.Crossing)
        {
            var other=c.RedPassage?c.Shelter:c.Prize;
            var marker=S(other,.92f);
            if(new Rect2(new(58,130),Size-new Vector2(116,340)).HasPoint(marker))
            {
                string lane=c.RedPassage?"Sheltered gate":c.PrizeName;
                float mw=text.GetStringSize(lane,fontSize:15).X+24;
                Box(marker.X-mw*.5f,marker.Y-27,mw,27,c.RedPassage?Mint:brass);
                Text(lane,marker.X-mw*.5f+12,marker.Y-8,15,c.RedPassage?Mint:brass);
            }
            DrawPolyline(Ring(c.Shelter,132),new Color(Mint,.68f),2,true);
            DrawPolyline(Ring(c.Prize,130),new Color(brass,.68f),2,true);
        }
        var bearing=target-ship.Position;
        var tagSize=text.GetStringSize(name,fontSize:17);
        float tagW=Math.Max(143,tagSize.X+32);
        var anchor=new Vector2(Math.Clamp(goal.X,tagW/2+20,w-tagW/2-20),Math.Clamp(goal.Y-31,150,h-188));
        bool off=(anchor-goal).Length()>74;
        if(off)
        {
            var dir=(goal-anchor).Normalized();var ortho=new Vector2(-dir.Y,dir.X);
            var tip=anchor+new Vector2(dir.X*tagW*.45f,dir.Y*24);
            DrawColoredPolygon([tip+dir*12,tip+ortho*6,tip-ortho*6],brass);
        }
        Box(anchor.X-tagW/2,anchor.Y-25,tagW,48,brass);
        Text(name,anchor.X-tagW/2+10,anchor.Y-5,17,Cream,true);
        int cables=(int)MathF.Round(bearing.Length()/100);
        string direction = $"{Bearing(bearing)}   ·   {cables} {(cables==1?"cable":"cables")}";
        Text(direction,anchor.X-tagW/2+10,anchor.Y+15,14,brass);
        if(c.Phase==ChartPhase.Running && !c.Docked)
        {
            var berth=c.Mooring-ship.Position;
            int nautical=Math.Max(1,(int)Math.Round(berth.Length()/100));
            string label=$"Pilot mooring    {Bearing(berth)}   ·   {nautical} {(nautical==1?"cable":"cables")}";
            float meter=text.GetStringSize(label,fontSize:14).X+22;
            Box(22,104,meter,26,Mint);Text(label,33,123,14,Mint);
        }
        if(c.Phase==ChartPhase.Running && !c.Docked && V2.Distance(ship.Position,c.Mooring)<730)
        {
            var p=S(c.Mooring,1.65f);
            Box(p.X-82,p.Y-24,164,28,Mint);
            Text("Q  ·  Pilot mooring",p.X-71,p.Y-4,15,Mint);
        }
        Box(22,18,373,85,brass);
        Text($"{(string.IsNullOrEmpty(c.Order.Island)?c.Region:c.Order.Island).ToUpperInvariant()}     /     LEG {c.Leg} OF {c.Order.Legs}",38,45,15,brass);
        Text(c.Order.Title,38,80,27,Cream,true);
        if(c.Writ.Quiet && c.Phase==ChartPhase.Running)
        {
            Box(w-230,18,208,52,brass);
            Text($"Noise   {c.Notice*100:0}%",w-212,48,17,c.Notice>.68f?Red:Mint);
        }
        if(c.Phase==ChartPhase.Boss && c.Captain is {} captain)
        {
            const int bar=260;
            Box(w-bar-28,18,bar,76,brass);
            Text(c.Order.Boss,w-bar-13,50,23,Cream,true);
            Text(c.Tell>0?c.AttackName.ToUpperInvariant():c.BossCovered?"ARMORED":"EXPOSED",w-bar-13,71,12,c.BossCovered?brass:Mint);
            DrawRect(new(w-bar-13,80,bar-30,5),new Color("455863"));
            DrawRect(new(w-bar-13,80,(bar-30)*Math.Clamp(captain.Health/captain.MaxHealth,0,1),5),Red);
        }
        Box(22,h-92,271,72,brass);
        Text($"Hull   {Math.Ceiling(ship.Health)} / {ship.MaxHealth:0}",37,h-65,18,Cream);
        Text($"{c.Purse} silver",195,h-65,16,brass);
        DrawRect(new(37,h-54,240,7),new Color("455863"));
        DrawRect(new(37,h-54,240*Math.Clamp(ship.Health/ship.MaxHealth,0,1),7),ship.Health<35?Red:Mint);
        Text($"E  Patch ×{c.Kits}    ·    Surge {ship.Boost:0}%",37,h-29,14,Mint);
        Box(w-385,h-92,363,72,brass);
        Text($"WASD  Helm     Space / click  Gun     Shift  Surge",w-374,h-66,15,Cream);
        Text(c.HookCooldown>0?$"Q   Line coiling   {Math.Ceiling(c.HookCooldown)}s":"Q   Crew line ready",w-374,h-39,16,Mint);
        string order=c.HelmOrder;
        float orderW=text.GetStringSize(order,fontSize:17).X+34;
        Box((w-orderW)/2,h-147,orderW,39,brass);
        Text(order,(w-orderW)/2+17,h-122,17,Cream);
        string crew=c.Tether!=null?(c.SeamReady?"Vara    Turn side-on and fire at the brass seam!":"Lio    Sail across her bow to expose the soft side!") : c.CrewLine;
        if((c.Tether!=null||c.Speech>0) && crew!=order)
        {
            float talkW=text.GetStringSize(crew,fontSize:17).X+34;
            Box((w-talkW)/2,h-195,talkW,35,Mint);
            Text(crew,(w-talkW)/2+17,h-172,17,Mint);
        }
    }
    string Bearing(V2 d)
    {
        string[] directions=["E","SE","S","SW","W","NW","N","NE"];
        return directions[((int)MathF.Round(MathF.Atan2(d.Y,d.X)/(MathF.PI/4))+8)%8];
    }
    Vector2[] Ring(V2 p,float r)
    {
        var result=new Vector2[41];
        for(int i=0;i<result.Length;i++)
        {
            float a=i*Mathf.Tau/40;
            result[i]=S(p+new V2(MathF.Cos(a),MathF.Sin(a))*r,.035f);
        }
        return result;
    }
    void CommanderTell()
    {
        var c=Course;
        foreach(var zone in c.Threats)
        {
            if(V2.DistanceSquared(zone.Start,zone.End)<1)
            {
                DrawPolyline(Ring(zone.Start,zone.Radius),Red,3,true);
                if(zone.Eye>0)DrawPolyline(Ring(zone.Start,zone.Eye),Mint,3,true);
                else DrawPolyline(Ring(zone.Start,Math.Max(6,zone.Radius*c.WarningProgress)),Cream,2,true);
            }
            else
            {
                var axis=OceanWorld.Unit(zone.End-zone.Start);
                var side=new V2(-axis.Y,axis.X)*zone.Radius;
                Vector2[] corners=[S(zone.Start-side),S(zone.Start+side),S(zone.End+side),S(zone.End-side)];
                DrawColoredPolygon(corners,new Color(Red,.18f+c.WarningProgress*.16f));
                DrawPolyline([..corners,corners[0]],Red,3,true);
            }
        }
    }

    void Weather(Color dye)
    {
        var weather=Course.Weather;
        var p=S(weather.Center);
        if(!new Rect2(new(-200,-200),Size+Vector2.One*400).HasPoint(p))return;
        var climate=Course.Country.Climate;
        bool current=climate is SeaClimate.Delta or SeaClimate.Loom;
        Color tint=current||climate==SeaClimate.Orchard?dye:Red;
        float radius=weather.Radius*(climate switch {SeaClimate.Choir=>Math.Max(.06f,weather.Windup),SeaClimate.Drum=>Math.Max(.06f,1-weather.Windup),_=>1});
        if(climate is SeaClimate.Wax or SeaClimate.Pitch or SeaClimate.Bottle or SeaClimate.Calving)tint=dye;
        if(climate>=SeaClimate.Salt && new Rect2(new Vector2(85,135),Size-new Vector2(170,343)).HasPoint(p))
        {
            string guide=climate switch
            {
                SeaClimate.Salt=>"Brine rim  ·  Surge across",
                SeaClimate.Bottle=>"Air bottles  ·  Cease fire to recharge",
                SeaClimate.Wax=>"Courier stream  ·  Follow its turn",
                SeaClimate.Sleep=>"Breathing hollow  ·  Quiet sails",
                SeaClimate.Tin=>"Moon pull  ·  Surge free",
                SeaClimate.Drum=>"Returning ring  ·  Surge through",
                SeaClimate.Pitch=>"Tar slick  ·  Draw pursuit inside",
                _=>"Nursery wake  ·  Match its heading"
            };
            float tag=text.GetStringSize(guide,fontSize:14).X+20;
            Box(p.X-tag/2,p.Y+16,tag,25,dye);Text(guide,p.X-tag/2+10,p.Y+34,14,Cream);
        }
        var ring=Ring(weather.Center,radius);
        DrawColoredPolygon(ring[..^1],new Color(tint,.12f));
        DrawPolyline(ring,new Color(tint,.84f),3,true);
        if(current)
        {
            for(int k=-1;k<=1;k++)
            {
                var at=p+new Vector2(0,k*18);
                DrawPolyline([at+new Vector2(-16,0),at+new Vector2(12,0),at+new Vector2(4,-6)],dye,2,true);
            }
        }
        else if(weather.Windup>0 && climate!=SeaClimate.Choir)
            DrawPolyline(Ring(weather.Center,weather.Radius*(.22f+.76f*weather.Windup)),tint,2,true);
    }
}
