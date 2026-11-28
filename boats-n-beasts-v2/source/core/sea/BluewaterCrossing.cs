using System.Numerics;

namespace BoatsNBeasts.Core;

public sealed partial class BluewaterCourse
{
    public bool Crossing { get; private set; }
    public Vector2 Shelter { get; private set; }
    public Vector2 Prize { get; private set; }
    public string PrizeName => Order.Duty switch
    {
        SeaDuty.Convoy => "Gunboats’ cut",
        SeaDuty.Hunt => "Skittish outrider",
        SeaDuty.Sounding => "Deep reading",
        SeaDuty.Blockade => "Inspection drum",
        _ => "Loose deck cargo"
    };
    public string CrossingOrder => Order.Duty switch
    {
        SeaDuty.Convoy => "Thread shelter, or Q at the hot gate with all lighters for battle pay.",
        SeaDuty.Hunt => "Sail through shelter, or hook the darting outrider with Q to mark the quarry.",
        SeaDuty.Sounding => "Take the sheltered mark, or stop at the deep mark and sound with Q.",
        SeaDuty.Blockade => "Take shelter, or shoot the inspection drum before its mortar lands.",
        _ => "Slip through shelter, or take Lio into the wreckage and grapple the salvage."
    };
    bool crossGuards;
    float crossingClock, winchHealth;
    int trailClues;
    public bool WeatherRead { get; private set; }

    void SetCrossing()
    {
        var path = Target - Ship.Position;
        Crossing = path.LengthSquared() > 1300 * 1300;
        WeatherRead = false;
        if (!Crossing) return;
        var center = Ship.Position + path * .49f;
        var ahead = OceanWorld.Unit(path,course);
        var side = new Vector2(-ahead.Y,ahead.X) * (Leg % 2 == 0 ? -1 : 1);
        Prize = FindWater(center - side * 135,135);
        Shelter = FindWater(center + side * 455,125);
        if (Vector2.DistanceSquared(Prize,Shelter) < 280*280)
            Shelter = FindWater(Prize + side * 460 + ahead * 130,120);
        winchHealth = 22 + Order.Tier * 3;
        crossGuards = false;
        crossingClock = 0;
        Weather.Set(Prize,Leg,Station);
    }

    bool NavigateCrossing(float dt,bool hook)
    {
        crossingClock += dt;
        float hot = Vector2.Distance(Ship.Position,Prize);
        float safe = Vector2.Distance(Ship.Position,Shelter);
        if (!crossGuards && Math.Min(hot,safe) < 725)
        {
            crossGuards = true;
            var direction = OceanWorld.Unit(Shelter-Prize);
            Ship.DropPatrol(Order.Duty == SeaDuty.Convoy ? EnemyKind.Serpent : Raider(Station),Prize + direction*175,1+Order.Tier*.05f,false);
            if(RedPassage || Order.Tier >= 4) Ship.DropPatrol(EnemyKind.Ray,Prize - direction*220,1,false);
        }
        if (safe < 140)
        {
            foreach (var enemy in Ship.Enemies)
                if (Vector2.DistanceSquared(enemy.Position,Shelter)<360*360) enemy.Stunned = 2;
            foreach (var craft in fleet) craft.Health = Math.Min(craft.Maximum,craft.Health+5);
            ClearCrossing(false);
            return true;
        }
        if (Order.Duty == SeaDuty.Hunt)
        {
            Prize += new Vector2(MathF.Cos(crossingClock*1.2f)*73,MathF.Sin(crossingClock*.96f)*46)*dt;
            if(hook && hot<HookReach) {HookAt(Prize);trailClues++;ClearCrossing(true);return true;}
        }
        else if (Order.Duty == SeaDuty.Blockade)
        {
            if(hot<630) Threaten(Prize,Ship.Position+Ship.Velocity*.22f,3.6f);
            if(DamageProp(Prize,ref winchHealth)) {ClearCrossing(true);return true;}
        }
        else if(hook && hot < (Order.Duty == SeaDuty.Salvage ? 290 : 180))
        {
            if(Order.Duty==SeaDuty.Sounding && Ship.Velocity.Length()>162)
                Say("Lio    Ease the sail. The lead's skipping along the surface.");
            else if(Order.Duty==SeaDuty.Convoy && fleet.Any(b=>Vector2.Distance(b.Position,Prize)>650))
                Say("Vara    Bring up the last lighter before I fire the signal!");
            else
            {
                if(Order.Duty==SeaDuty.Salvage) Kits++;
                if(Order.Duty==SeaDuty.Sounding) WeatherRead=true;
                HookAt(Prize);
                ClearCrossing(true);
            }
            return true;
        }
        if(hook) HookEnemy();
        return true;
    }

    void ClearCrossing(bool prize)
    {
        Crossing=false;
        if(prize) {Purse+=2+Math.Min(Order.Tier,5);Ship.Xp+=3;}
        Alarm=0;
        Weather.Set(Target,Leg,Station);
        Say(prize ? "Vara    The pennant's down. The watch has earned its share." : "Lio    Clear water on the other side. Bring her around.");
    }
}
