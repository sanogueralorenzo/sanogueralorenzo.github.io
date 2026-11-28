using System.Numerics;

namespace BoatsNBeasts.Core;

public enum SeaClimate { Cinder, Delta, Orchard, Shelf, Loom, Choir, Court, Storm, Salt, Bottle, Wax, Sleep, Tin, Drum, Pitch, Calving }

public sealed record SeaCountry(SeaClimate Climate, string Watermark, string Anchorage, string Accent, string Shadow)
{
    public static SeaCountry At(string region, string island = "")
    {
        var chart = Mainland(region);
        if(string.IsNullOrEmpty(island))return chart;
        uint seed=23;
        foreach(char letter in island)seed=unchecked(seed*31+letter);
        var random=new SeedRandom(seed);
        int pigment=Convert.ToInt32(chart.Accent,16);
        int Tone(int value) => Math.Clamp(value+(int)random.Range(-24,25),0,255);
        string dye=$"{Tone(pigment>>16):x2}{Tone((pigment>>8)&255):x2}{Tone(pigment&255):x2}";
        return chart with {Accent=dye,Anchorage=$"{island} mooring"};
    }
    static SeaCountry Mainland(string region) => region switch
    {
        "The Saltstep Terraces" => new(SeaClimate.Salt,"Rising salt pan","Brine stair","e8c1a2","745a71"),
        "Bottlebrush Reach" => new(SeaClimate.Bottle,"Breathing bottle","Root glass landing","8ecbb4","3f6868"),
        "Waxwing Roads" => new(SeaClimate.Wax,"Courier stream","Red seal roost","eb9f71","624b61"),
        "The Sleeping Narrows" => new(SeaClimate.Sleep,"Sleeper’s breath","Folding ward","a8bdab","4c5c6b"),
        "Tinmoon Anchorage" => new(SeaClimate.Tin,"Moon pull","Diving bell pier","afbed4","51516d"),
        "Drumskin Gulf" => new(SeaClimate.Drum,"Drumhead ripple","Taut cord pier","e6b178","634964"),
        "Pitchwake Strait" => new(SeaClimate.Pitch,"Tar slick","Anchor steps","dba372","53495c"),
        "The Calving Sea" => new(SeaClimate.Calving,"Nursery wake","First-light strand","aaceac","596179"),
        "Reedglass Delta" => new(SeaClimate.Delta, "Millrace", "Reedcutters’ steps", "b3d581", "354860"),
        "Hanging Orchard" => new(SeaClimate.Orchard, "Pollen fall", "Lantern bower", "e48f9d", "673d59"),
        "Whitewake Shelf" => new(SeaClimate.Shelf, "Breaking floe", "Glass spring", "badceb", "4b496a"),
        "Tangleloom Sound" => new(SeaClimate.Loom, "Crosswind", "Sailmakers’ raft", "e3afca", "4a486c"),
        "Choir Deep" => new(SeaClimate.Choir, "Echo reef", "Quiet pool", "b49fe2", "49456d"),
        "Sable Court" => new(SeaClimate.Court, "Customs lantern", "Clerks’ lighter", "d7ba89", "443c5a"),
        "The Unnumbered Sea" => new(SeaClimate.Storm, "Starfall", "Navigators’ lee", "e5cc97", "3c4869"),
        _ => new(SeaClimate.Cinder, "Kiln vent", "Coal rose mooring", "e69d68", "583c5b")
    };
}

public sealed partial class SeaWeather(SeaCountry country)
{
    public float Clock { get; private set; }
    public Vector2 Center { get; private set; }
    public float Windup { get; private set; }
    public bool Marked { get; private set; }
    public float Radius { get; private set; }
    float cycle, exposure;
    Vector2 source;

    public void Set(Vector2 near, int leg, int station)
    {
        source = near + new Vector2((station % 2 == 0 ? 1 : -1) * 155, -84);
        Center = source;
        Radius = country.Climate switch { SeaClimate.Court => 190, SeaClimate.Storm => 142, SeaClimate.Choir => 270, _ => 165 };
        cycle = 0;
        Clock = leg + station * 2;
        exposure = 0;
        Marked = false;
    }

    public void Tick(float dt, Voyage ship, int tier)
    {
        Clock += dt;
        var offset = ship.Position - source;
        if (offset.LengthSquared() > 820 * 820) { Marked = false; return; }
        cycle += dt;
        float period = Math.Max(3.7f, 6.8f - tier * .18f);
        if(WalkingWater(ship,dt,period))
        {
            if(cycle>=period)cycle=0;
            return;
        }
        switch (country.Climate)
        {
            case SeaClimate.Delta:
            case SeaClimate.Loom:
                Center = source;
                Marked = true;
                Windup = (1 + MathF.Sin(Clock * .77f)) * .5f;
                if (offset.Length() < Radius)
                {
                    var current = country.Climate == SeaClimate.Delta ? new Vector2(112, -34) : new Vector2(-128, 57);
                    ship.Position = ship.World.Slide(ship.Position, ship.Position + current * dt * (.55f + Windup), 40);
                }
                break;
            case SeaClimate.Orchard:
            case SeaClimate.Court:
                Center = source + new Vector2(MathF.Cos(Clock * .54f), MathF.Sin(Clock * .54f)) * 114;
                Marked = true;
                Windup = Math.Clamp(exposure / 1.2f, 0, 1);
                if (Vector2.Distance(ship.Position, Center) < Radius)
                {
                    exposure += dt;
                    if (exposure >= 1.2f)
                    {
                        if (country.Climate == SeaClimate.Orchard) ship.Boost = Math.Min(100, ship.Boost + 24);
                        ship.Spawn(country.Climate == SeaClimate.Court ? EnemyKind.Serpent : EnemyKind.Ray);
                        exposure = -3;
                    }
                }
                else exposure = Math.Max(0, exposure - dt * .6f);
                break;
            case SeaClimate.Choir:
                Marked = true;
                Center = source;
                Windup = cycle / period;
                if (Math.Abs(offset.Length() - Radius * Windup) < 14 && !ship.IsBoosting) ship.HullHit(7 + tier);
                break;
            default:
                if (cycle < .65f)
                    Center = country.Climate == SeaClimate.Storm ? ship.Position + ship.Velocity * .48f :
                        source + new Vector2(MathF.Sin(Clock * .7f) * 102, MathF.Cos(Clock) * 47);
                Windup = Math.Clamp((cycle - (period - 1.65f)) / 1.65f, 0, 1);
                Marked = Windup > 0;
                if (cycle >= period)
                {
                    ship.Events.Add(new("bossExplosion", Center, Radius));
                    if (Vector2.Distance(Center, ship.Position) < Radius && !ship.IsBoosting) ship.HullHit(9 + tier * 1.8f);
                    if (country.Climate == SeaClimate.Shelf && Vector2.Distance(Center, ship.Position) < Radius * 1.25f)
                        ship.Velocity += OceanWorld.Unit(ship.Position - Center) * 185;
                }
                break;
        }
        if (cycle >= period) cycle = 0;
    }
}
