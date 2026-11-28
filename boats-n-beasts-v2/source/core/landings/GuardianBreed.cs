namespace BoatsNBeasts.Core;

public enum GuardianForm { Regional, Bird, Cat, Drake, Insect, Serpent, Shell, Weaver, Machine }

internal static class GuardianBreed
{
    public static GuardianForm Named(string name)
    {
        var n = name.ToLowerInvariant();
        bool Any(params string[] tokens) => tokens.Any(n.Contains);
        if (Any("heron", "gull", "swift", "grouse", "pigeon", "tern", "kite", "owl", "rook", "skua", "finch", "wren", "egret", "crow", "ibis", "crane")) return GuardianForm.Bird;
        if (Any("lynx", "jackal", "terrier", "fox", "mastiff", "dog", "badger", "mole", "hare", "stoat", "hound", "vixen", "weasel", "mouse", "rat", "cat", "marmot", "goat")) return GuardianForm.Cat;
        if (Any("adder", "snake", "lamprey", "serpent", "eel", "python", "skink")) return GuardianForm.Serpent;
        if (Any("hornet", "wasp", "moth", "bee", "fly", "locust")) return GuardianForm.Insect;
        if (Any("beetle", "borer", "tick", "turtle", "clam", "crab", "snail", "weevil", "mite", "tortoise")) return GuardianForm.Shell;
        if (Any("spider", "widow", "weaver")) return GuardianForm.Weaver;
        if (Any("balance", "clock", "jack", "warden", "spindle", "gauge", "hammer", "winder", "wheel")) return GuardianForm.Machine;
        if (Any("drake", "lizard", "newt", "saur")) return GuardianForm.Drake;
        return GuardianForm.Regional;
    }
}
