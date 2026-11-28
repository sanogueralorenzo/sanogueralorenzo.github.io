using System.Numerics;

namespace BoatsNBeasts.Core;

public sealed partial class LandingYard
{
    public string JobTitle(LandingJob job) => job switch
    {
        LandingJob.Weights => "Seal room",
        LandingJob.Nets => "Drift berth",
        LandingJob.Mould => "Pin foundry",
        LandingJob.Escort => "Workers’ lock",
        LandingJob.Capstans => "Winch house",
        _ => "Toll inspection"
    };
    public Vector2 Mark(int index)
    {
        Vector2[] local = [new(-1.40f, -.63f), new(.07f, 1.46f), new(1.36f, -.53f)];
        if (Job == LandingJob.Weights || Job == LandingJob.Breakers)
        {
            if (index == 0) return Workbench + local[0];
            if (index == 1) return Plan.Wayhouse;
            return Plan.Bells[1 - Branch] + local[2];
        }
        return Workbench + local[index];
    }
    public Vector2 Float(int index)
    {
        float angle = (index == 0 ? -.5f : index == 1 ? 1.42f : 3.28f) + MathF.Sin(Clock * .68f + index) * .22f;
        return Workbench + new Vector2(2.85f * MathF.Cos(angle), 2.58f * MathF.Sin(angle));
    }
    void BeginJob()
    {
        Phase = YardPhase.Work; ClearJob();
        Billet = Workbench + new Vector2(-.9f, -.4f); Passenger = Mark(Branch == 0 ? 2 : 0);
        Say(Job switch
        {
            LandingJob.Weights => "Read the three seals on the register. Press E at each matching clay tablet.",
            LandingJob.Nets => "The tide has carried three corked lines out. Follow the rim and call Lio’s hook with K.",
            LandingJob.Mould => $"Position behind the {Region.Pin}. J knocks it into the striped seat. K draws it back.",
            LandingJob.Escort => $"One {Region.Castaway} is stranded on the slip. Help them up with E and lead them to the lower wharf.",
            LandingJob.Capstans => "Crank the marked winches with E. Mind the travelling counterweights on the track.",
            _ => "Three guard seals. Cut the two cargo lids with J and lift the iron lid at the lower landing with K."
        });
    }
    void JobStep()
    {
        if (++Progress >= 3)
        {
            if (Job == LandingJob.Nets) { Carrying = true; Say("The net has all three floats. Carry the catch to the marked crane in the upper slip."); }
            else CompleteJob();
        }
        else Say(Job == LandingJob.Weights || Job == LandingJob.Capstans ? "Next mark  ·  " + Region.Marks[Sequence[Progress]] : "Line clear. Keep moving.");
    }
    void CompleteJob()
    {
        Completed[Branch] = true; Phase = YardPhase.Crossroads;
        Chits += Branch == 0 ? 2 : 3; Silver += 2;
        Say(Completed.All(x => x) ? "Both yards are open. Take either high walk to the freight gate." : "You have the freight stamp. Work the other yard for extra chits, or head to the upper gate.");
    }
    void BeginFinal()
    {
        Braced = false; PassengerFree = false; trail.Clear(); billetVelocity = Vector2.Zero;
        Passenger = Plan.Summit + new Vector2(-2.15f, -1.26f);
        Billet = FinalSite + new Vector2(-.79f, .59f);
        Say(FinalStep.Instruction + ".");
    }
    void AdvanceFinal()
    {
        Silver += 2;
        if (++FinalIndex == contract.Length) { Phase = YardPhase.Departure; Say("The work is done. Board the marked ferry together."); return; }
        Phase = YardPhase.Release; BeginFinal();
    }
    bool FinishWork(float dt, bool cut, bool hook)
    {
        bool used = false;
        switch (FinalStep.Action)
        {
            case LandingAction.Cut when cut && Near(FinalSite, 1.3f): AdvanceFinal(); break;
            case LandingAction.Haul when hook && Near(FinalSite, 3.1f):
                Hook = .53f; HookWait = 1.0f; HookEnd = FinalSite; used = true; AdvanceFinal(); break;
            case LandingAction.Brace when hook && Near(FinalSite, 2.65f):
                Hook = .55f; HookWait = 1; HookEnd = FinalSite; Braced = true; used = true; Say("Lio holds the weight. Use the free lever with E."); break;
            case LandingAction.Seat:
                if (hook && Near(Billet, 3.3f)) { Hook = .44f; HookWait = 1; HookEnd = Billet; billetVelocity = Unit(Player - Billet) * 3.6f; used = true; }
                if (cut && Near(Billet, 1.3f)) billetVelocity = Unit(Billet - Player) * 4.8f;
                Billet = Walkable(Billet + billetVelocity * dt); billetVelocity *= MathF.Exp(-5 * dt);
                if (Vector2.Distance(Billet, FinalSite) < .40f) AdvanceFinal();
                break;
            case LandingAction.Guide when PassengerFree:
                FollowWorker(dt);
                if (Vector2.Distance(Passenger, DeliverTo) < 1.25f) { RescuedPassenger = true; AdvanceFinal(); }
                break;
        }
        return used;
    }
    void FollowWorker(float dt)
    {
        if (Vector2.DistanceSquared(lastTrail, Player) > .055f) { lastTrail = Player; trail.Enqueue(Player); }
        if (trail.TryPeek(out var next) && Vector2.Distance(Passenger, Player) > .82f)
        {
            var step = next - Passenger;
            if (step.Length() < .065f) trail.Dequeue(); else Passenger += Unit(step) * Math.Min(step.Length(), dt * (Outfit == Loadout.Lifeboat ? 4.25f : 3.4f));
        }
    }
    bool Work(float dt, bool cut, bool hook)
    {
        bool used = false;
        if (Carrying) return false;
        switch (Job)
        {
            case LandingJob.Nets when hook:
                for (int i = 0; i < 3; i++) if (!Secured[i] && Near(Float(i), 2.30f))
                {
                    HookEnd = Float(i); Hook = .5f; HookWait = .95f; used = true; Secured[i] = true; JobStep(); break;
                }
                break;
            case LandingJob.Mould:
                if (hook && Near(Billet, 3.5f)) { HookEnd = Billet; Hook = .4f; HookWait = 1; used = true; billetVelocity = Unit(Player - Billet) * 3.8f; }
                if (cut && Near(Billet, 1.3f)) billetVelocity = Unit(Billet - Player) * 4.8f;
                Billet += billetVelocity * dt; billetVelocity *= MathF.Exp(-5 * dt);
                var norm = (Billet - Workbench) / new Vector2(1.7f, 1.48f);
                if (norm.LengthSquared() > 1) Billet = Workbench + Vector2.Normalize(norm) * new Vector2(1.7f, 1.48f);
                if (Vector2.Distance(Billet, Mould) < .43f) { Carrying = true; Say("The bronze is seated. Take the finished casting to the upper slip."); }
                break;
            case LandingJob.Escort when PassengerFree:
                FollowWorker(dt);
                if (!Intercept && Vector2.Distance(Passenger, Workbench) > 2.45f)
                {
                    Intercept = true; SpawnWatch(PassengerDock, false);
                    Say("The toll watch is waiting at the approach. Make room for the worker to pass.");
                }
                if (Foes.Count == 0 && Vector2.Distance(Passenger, PassengerDock) < 1.5f) CompleteJob();
                break;
            case LandingJob.Capstans:
                if (hook && !Anchored && Near(Workbench, 2.05f))
                { Anchored = true; Hook = .4f; HookWait = .95f; HookEnd = Workbench; used = true; Say("The cable is fast. Turn the marked winch with E."); }
                if (safe == 0 && (Near(WeightAt(0), .45f) || Near(WeightAt(1), .45f))) Damage(1);
                break;
            case LandingJob.Breakers when cut || hook:
                for (int i = 0; i < 3; i++) if (!Secured[i] && (i == 1 ? hook : cut) && Near(Mark(i), i == 1 ? 2.85f : 1.25f))
                {
                    if (i == 1) { used = true; Hook = .45f; HookWait = 1; HookEnd = Mark(i); }
                    Secured[i] = true; JobStep(); break;
                }
                break;
        }
        return used;
    }
}
