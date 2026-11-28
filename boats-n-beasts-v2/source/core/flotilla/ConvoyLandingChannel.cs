namespace BoatsNBeasts.Core;

public enum TideCell { Water, Bar, Battery, Bales, Lifeline, Eddy, Workshop, Lantern, Bond }
public sealed class ConvoyChannel
{
    public const int Lanes=5;
    public readonly int Reaches;
    public readonly TideCell Specialty;public readonly string Landmark;
    public readonly TideCell[,] Water;
    public readonly int[] Lane=[0,2,4],Row=[0,0,0],Rudder=[0,0,0];
    public readonly int[] PreviousLane=[0,2,4],PreviousRow=[0,0,0];
    public int Signals {get;private set;}
    public float LastSignalAt {get;private set;}=-10;
    public ConvoyChannel(int seed,int district,IslandClimate climate)
    {
        (Specialty,Landmark)=climate switch{
            IslandClimate.Kiln=>(TideCell.Workshop,"Kiln tender"),IslandClimate.Delta=>(TideCell.Eddy,"Silt eddy"),IslandClimate.Orchard=>(TideCell.Lantern,"Pear lamp"),
            IslandClimate.Shelf=>(TideCell.Workshop,"Stove punt"),IslandClimate.Loom=>(TideCell.Bond,"Rope toll"),IslandClimate.Reef=>(TideCell.Eddy,"Singing current"),
            IslandClimate.Court=>(TideCell.Bond,"Bond lighter"),IslandClimate.Stars=>(TideCell.Lantern,"Star watch"),IslandClimate.Saltstep=>(TideCell.Eddy,"Root race"),
            IslandClimate.Bottlebrush=>(TideCell.Workshop,"Glass tender"),IslandClimate.Waxwing=>(TideCell.Lantern,"Wax beacon"),IslandClimate.Narrows=>(TideCell.Lantern,"Dream lamp"),
            IslandClimate.Tinmoon=>(TideCell.Workshop,"Tin repair punt"),IslandClimate.Drumskin=>(TideCell.Eddy,"Skin undertow"),IslandClimate.Pitchwake=>(TideCell.Bond,"Tar toll"),
            _=>(TideCell.Lantern,"Nursery lamp")
        };
        Reaches=5+district;Water=new TideCell[Lanes,Reaches+1];var random=new Random(seed);
        for(int row=1;row<Reaches;row++)
        {
            int reef=(random.Next(5)+(int)climate+row)%5;
            Water[reef,row]=TideCell.Bar;if(row%2==0)Water[(reef+2)%5,row]=TideCell.Bar;
            var available=Enumerable.Range(0,5).Where(x=>Water[x,row]==TideCell.Water).OrderBy(_=>random.Next()).ToArray();
            Water[available[0],row]=row%2==0?TideCell.Lifeline:TideCell.Bales;
            Water[available[1],row]=TideCell.Battery;if(available.Length>2)Water[available[2],row]=Specialty;
        }
    }
    public bool Home(int boat)=>Row[boat]>=Reaches;
    public int Aimed(int boat)=>Lane[boat]+Rudder[boat];
    public bool Passable(int lane,int row)=>lane>=0&&lane<Lanes&&row>=0&&row<=Reaches&&Water[lane,row]!=TideCell.Bar;
    public void Turn(int i){if(!Home(i))Rudder[i]=Rudder[i] switch { 0=>-1,-1=>1,_=>0 };}
    public static string Bearing(int steer)=>steer<0?"port":steer>0?"starboard":"ahead";
    public bool Dredge(int i,MusterBoat boat)
    {
        int x=Aimed(i),row=Row[i]+1;if(Home(i)||x<0||x>=Lanes||boat.Stores<=0||Water[x,row]!=TideCell.Bar)return false;
        Water[x,row]=TideCell.Water;boat.Stores--;return true;
    }
    public (int Silver,string Report) Sound(MusterBoat[] boats,float clock)
    {
        Signals++;LastSignalAt=clock;Array.Copy(Lane,PreviousLane,3);Array.Copy(Row,PreviousRow,3);
        var occupied=boats.Where(b=>b.Hull>0&&!Home(b.Index)).Select(b=>(Lane[b.Index],Row[b.Index])).ToHashSet();
        var moved=new List<int>();var reports=new List<string>();int silver=0;
        foreach(var boat in boats.Where(b=>b.Hull>0&&!Home(b.Index)).OrderByDescending(b=>Row[b.Index]).ThenBy(b=>(b.Index+Signals)%3))
        {
            int i=boat.Index,lane=Aimed(i),row=Row[i]+1;
            if(!Passable(lane,row)){reports.Add($"{boat.Name} holds at the bar");continue;}
            if(row<Reaches&&occupied.Contains((lane,row))){reports.Add($"{boat.Name} yields the channel");continue;}
            occupied.Remove((Lane[i],Row[i]));if(row<Reaches)occupied.Add((lane,row));Lane[i]=lane;Row[i]=row;moved.Add(i);
        }
        foreach(int i in moved.OrderBy(i=>boats[i].Index))
        {
            var b=boats[i];int x=Lane[i],row=Row[i];
            switch(Water[x,row])
            {
                case TideCell.Battery:
                    bool cover=boats.Any(v=>v!=b&&v.Hull>0&&v.People>0&&Row[v.Index]==row&&Math.Abs(Lane[v.Index]-x)==1);
                    if(b.Timbers>0){b.Timbers--;reports.Add($"{b.Name}’s breastwork catches the shot");}
                    else if(cover)reports.Add($"an escort screens {b.Name}");
                    else{b.Hull=Math.Max(0,b.Hull-2);reports.Add(b.Hull>0?$"{b.Name} takes two hull damage":$"{b.Name} grounds under the battery");}
                    break;
                case TideCell.Workshop:b.Hull=Math.Min(8,b.Hull+2);Water[x,row]=TideCell.Water;reports.Add($"{Landmark} patches {b.Name}");break;
                case TideCell.Bond:
                    if(b.Stores>0){b.Stores--;reports.Add($"{b.Name} pays the lighter with a fitting");}
                    else{b.Hull=Math.Max(0,b.Hull-1);reports.Add($"{b.Name} scrapes the unpaid chain");}break;
                case TideCell.Lantern:
                    for(int j=Math.Max(0,x-1);j<=Math.Min(4,x+1);j++)if(row<Reaches&&Water[j,row+1]==TideCell.Bar)Water[j,row+1]=TideCell.Water;
                    reports.Add($"{Landmark} marks a safe cut ahead");Water[x,row]=TideCell.Water;break;
                case TideCell.Eddy:
                    int push=x==4?x-1:x+1;
                    if(Passable(push,row)&&!occupied.Contains((push,row))){occupied.Remove((x,row));occupied.Add((push,row));Lane[i]=push;Rudder[i]=0;reports.Add($"{b.Name} rides the eddy one lane over");}break;
                case TideCell.Bales:b.Stores++;silver+=2;Water[x,row]=TideCell.Water;reports.Add($"{b.Name} saves a fitting and two silver");break;
                case TideCell.Lifeline:b.People++;Water[x,row]=TideCell.Water;reports.Add($"{b.Name} takes a swimmer aboard");break;
            }
            if(Home(i))reports.Add($"{b.Name} makes the release berth");
        }
        if(reports.Count==0)reports.Add("The convoy clears a reach.");
        return(silver,string.Join(" · ",reports));
    }
}
