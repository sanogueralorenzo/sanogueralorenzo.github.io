using Godot;
using BoatsNBeasts.Core;
using N2=System.Numerics.Vector2;
namespace BoatsNBeasts;

internal partial class UnderHud:Control
{
    public UnderwaysExpedition Trip=null!;
    static readonly Color Ink=new("142d39ef"),Gold=new("eec780"),Paper=new("fff0cf"),Mint=new("9ae4c8");
    Font font=null!;
    public override void _Ready(){MouseFilter=MouseFilterEnum.Ignore;font=ThemeDB.FallbackFont;}
    public override void _Draw()
    {
        var y=Trip.Crawl;float w=Size.X,h=Size.Y;
        if(y.ChartOpen){if(Trip.NotesOpen)Casebook(y);else Chart(y);return;}
        float wide=Math.Min(w*.56f,740);Panel(new(18,16,wide,105));
        Text(34,42,$"{(y.Order.Island.Length>0?y.Order.Island:y.Order.Region).ToUpperInvariant()}   ·   UNDERWAYS   {y.Depth+1} / {y.Floors}",16,Gold);
        Text(34,70,y.Floor.Name(y.Room),24,Paper);Text(34,100,y.Hint,17,Mint,wide-30);
        if(y.Room.Foes.FirstOrDefault(f=>f.Kind==YardBeast.Guardian) is {} boss)
        {
            Panel(new(w-343,16,326,66));Text(w-329,43,y.GuardianName,20,Gold);DrawRect(new(w-330,56,300,8),new("664953"));DrawRect(new(w-330,56,300f*boss.Health/boss.Maximum,8),new("eb9567"));
        }
        var at=Trip.Stage.Lens;
        void Label(N2 p,string value,Color color)
        {
            var pos=at.UnprojectPosition(UnderRoomArt.Place(p,N2.DistanceSquared(y.Player,p)<.78f?1.15f:.34f));float width=font.GetStringSize(value,fontSize:15).X+14;
            pos=pos.Clamp(new Vector2(width/2+14,143),new Vector2(w-width/2-14,h-111));
            Panel(new(pos.X-width/2,pos.Y-11,width,23));Text(pos.X-width/2+7,pos.Y+6,value,15,color);
        }
        foreach(var door in y.Floor.Exits(y.Here))
        {
            var p=y.Floor.Threshold(y.Here,door);var next=y.Floor.Rooms[door.Other(y.Here)];bool nearby=N2.DistanceSquared(y.Player,p)<2.25f;
            string label=(nearby?"E  ":"")+y.Floor.Name(next)+y.DoorRule(door);
            Label(p,label,y.CanOpen(door)?Mint:Gold);
        }
        if(y.Room.Rail is {} rail&&!rail.Done)Label(rail.At(rail.Asked+7),SwitchRail.Berth(rail.Asked),Mint);
        if(y.Room.Mosaic is {} print)
        {
            for(int i=0;i<9;i++)if(print.Tiles[i]>0)
            {
                var atTile=at.UnprojectPosition(UnderRoomArt.Place(TornChart.At(i),.23f));Text(atTile.X-5,atTile.Y,print.Tiles[i].ToString(),18,print.Suggested==i?Mint:Paper);
            }
        }
        foreach(var (p,label) in y.WorkMarks())Label(p,label,Gold);
        foreach(var f in y.Room.Foes.Where(f=>f.Kind!=YardBeast.Guardian)){var p=at.UnprojectPosition(UnderRoomArt.Place(f.Position,1.23f));DrawRect(new(p.X-16,p.Y,32,4),Ink);DrawRect(new(p.X-16,p.Y,32f*f.Health/f.Maximum,4),Gold);}
        if(y.AtSurfaceLift&&N2.Distance(y.Player,y.Winch)<1.7f)
        {
            Panel(new(18,132,502,107));Text(33,158,"Where the shaft opens to daylight",18,Gold);
            Text(33,186,"E    Witness road · Three districts, two rations and a chart lamp",15,Paper);
            Text(33,211,"2    Bonded yards · Four districts, two edge fittings and three powder",15,Paper);
        }
        if(y.AtBench&&!y.Room.Gift)
        {
            Panel(new(18,132,390,112));Text(33,157,y.Room.Trial==UnderTrial.Camp?"Fit one for two work chits":"Take one fitting",17,Gold);
            var offers=y.Offers();for(int i=0;i<3;i++)Text(33,182+i*24,$"{i+1}   {UnderwayRun.GiftText(offers[i])}",16,Paper);
        }
        if(y.MessageClock>0&&!y.Lost&&y.Message!=y.Hint)
        {
            float width=Math.Min(w*.79f,font.GetStringSize(y.Message,fontSize:17).X+28);
            float height=font.GetMultilineStringSize(y.Message,HorizontalAlignment.Center,width-24,17).Y+15;
            var r=new Rect2((w-width)*.5f,h-83-height,width,height);Panel(r);
            DrawMultilineString(font,r.Position+new Vector2(12,21),y.Message,HorizontalAlignment.Center,width-24,17,-1,Paper);
        }
        Panel(new(18,h-72,w-36,55));Text(32,h-49,$"Vitality  {y.Vitality}/{y.Maximum}     Silver  {Trip.CarriedSilver+y.Silver}     Chits  {y.Chits}     Rations  {y.Rations}     Powder  {y.Powder}      {(y.Staff?"Staff key":"No staff key")}     Seals  {y.Keys}/{y.SealCost}",16,Mint);
        Text(32,h-26,"WASD  Move     J  Cut / push     K  Hook / pull     L  Vara     Space  Dodge     E  Work / door     1  Eat     M  Chart",16,Paper);
        if(y.Lost){DrawRect(new(0,0,w,h),new("132432cb"));DrawString(font,new(0,h*.45f),"The line crew hauls you home",HorizontalAlignment.Center,w,34,Paper);DrawString(font,new(0,h*.45f+49),$"E   Return with {Trip.CarriedSilver+y.Silver} silver",HorizontalAlignment.Center,w,21,Gold);}
    }
    void Chart(UnderwayRun y)
    {
        float w=Size.X,h=Size.Y;DrawRect(new(0,0,w,h),new("102b35f4"));var rooms=y.Floor.Rooms;
        Text(w*.065f,h*.11f,$"The Underways   ·   {y.RegionDistrict()}",31,Paper);
        Text(w*.065f,h*.16f,$"Deck {y.Depth+1}/{y.Floors}    ·    {y.Keys}/{y.SealCost} seals    ·    {(y.Staff?"Staff key acquired":"Work a front workshop for the staff key")}",18,Gold);
        Vector2 P(UnderRoom r)=>new(w*.10f+r.X*w*.134f,h*.25f+r.Y*h*.122f);
        foreach(var d in y.Floor.Doors)
        {
            var a=rooms[d.A];var b=rooms[d.B];if(!y.Seen(a)&&!y.Seen(b))continue;DrawLine(P(a),P(b),y.CanOpen(d)?new("889b89"):new("9c6f58"),d.Gate==UnderGate.Open?4:6);
        }
        foreach(var r in rooms)
        {
            var p=P(r);var rect=new Rect2(p-new Vector2(w*.064f,21),new(w*.128f,42));
            DrawRect(rect,r.Cleared&&r.Visited?new("355a51"):new("394553"));DrawRect(rect,r.Id==y.Here?Mint:r.Id==Trip.Selected?Gold:new("839380"),false,r.Id==Trip.Selected||r.Id==y.Here?3:1.2f);
            string title=y.Seen(r)?y.Floor.Name(r):"Unexplored";DrawString(font,new(rect.Position.X,p.Y-1),title,HorizontalAlignment.Center,rect.Size.X,15,Paper);
            string loot=y.Seen(r)?y.RewardName(r):"";DrawString(font,new(rect.Position.X,p.Y+15),r.Id==y.Here?"Crew":r.Cleared&&r.Visited?"Cleared":loot,HorizontalAlignment.Center,rect.Size.X,13,Gold);
        }
        var target=rooms[Trip.Selected];float left=w*.70f;Panel(new(left-15,h*.235f,w*.27f,h*.54f));
        Text(left,h*.28f,y.Seen(target)?y.Floor.Name(target):"Unexplored",22,Gold,w*.24f);
        string description=y.Seen(target)?(target.Trial switch{UnderTrial.Drain=>"Join the pressure pipes to the gold receivers to drain the cache. The pump crew also supplies powder.",UnderTrial.Rail=>"Route freight carts into their marked bays. Dispatch gives the crew a ration and access to the cache.",UnderTrial.Dig=>$"Follow the survey to recover {y.Parcel}. The assay office takes the sample.",UnderTrial.Assay=>"Set the three brass weights in either pan and reproduce the stamped measurements. File the case evidence beside the scales.",UnderTrial.Mirrors=>"Trace the light from the lantern to its receiver.",UnderTrial.Freight=>"Push two crates onto marked sockets. Lio can pull one clear of a corner.",UnderTrial.Watch=>"The watch carries work chits and loose silver. The return door stays open.",UnderTrial.Keeper=>"Bring both seal colors. Take the keeper’s register to the freight lift.",UnderTrial.Capstan=>"Split the crew between the counterweights and fitting drum.",UnderTrial.Cradle=>"Change the cradle track while keeping the load under tow.",UnderTrial.Rescue=>"Brace the frame, free the worker and escort them to the sling.",UnderTrial.Chart=>"Read the witness stamps, then repeat their order on the plates.",UnderTrial.Camp=>"Crew fittings cost two work chits. Match one seal of each color for archive pay.",UnderTrial.Stores=>"An unopened locker supplies one free fitting.",_=>y.Order.Brief}):"Visit an adjacent room or take a chart lamp to survey this chamber.";
        DrawMultilineString(font,new(left,h*.335f),description,HorizontalAlignment.Left,w*.225f,17,5,Paper);
        Text(left,h*.515f,"Crew notes",17,Mint);
        var notes=y.Journal.TakeLast(3).ToArray();for(int i=0;i<notes.Length;i++)DrawMultilineString(font,new(left,h*(.555f+i*.067f)),notes[i],HorizontalAlignment.Left,w*.225f,14,2,Paper);
        if(y.EvidenceRecord.Length>0)DrawMultilineString(font,new(w*.065f,h*.80f),$"{y.CaseItem} · {y.EvidenceRecord}",HorizontalAlignment.Left,w*.86f,17,2,Paper);
        Text(w*.065f,h*.91f,"Arrows   Inspect a room        Tab   Next room        J   Casebook        M   Close chart",19,Mint);
    }
    void Casebook(UnderwayRun y)
    {
        float w=Size.X,h=Size.Y;DrawRect(new(0,0,w,h),new("102b35f4"));
        float left=w*.10f,body=w*.80f;
        Text(left,h*.13f,y.Order.Title,31,Paper);Text(left,h*.20f,y.CaseItem,22,Gold);
        DrawMultilineString(font,new(left,h*.27f),y.Order.Objective,HorizontalAlignment.Left,body,18,2,Paper);
        string record=y.EvidenceRecord.Length==0?"The survey has yet to file its first sample.":y.EvidenceRecord;
        DrawMultilineString(font,new(left,h*.37f),record,HorizontalAlignment.Left,body,18,2,Mint);
        var entries=y.Journal.AsEnumerable().Reverse().Skip(Trip.NotePage*6).Take(6).ToArray();
        for(int i=0;i<entries.Length;i++)DrawMultilineString(font,new(left,h*(.47f+i*.059f)),entries[i],HorizontalAlignment.Left,body,16,2,Paper);
        Text(left,h*.91f,"Arrows   Turn page        J   Floor chart        M   Return to work",18,Gold);
    }
    void Panel(Rect2 r){DrawRect(r,Ink);DrawLine(r.Position,r.Position+new Vector2(r.Size.X,0),Gold,1.25f);}
    void Text(float x,float y,string value,int size,Color color,float width=-1)=>DrawString(font,new(x,y),value,HorizontalAlignment.Left,width,size,color);
}
