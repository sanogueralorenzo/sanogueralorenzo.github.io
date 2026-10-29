namespace CrestCore.Contracts;

public sealed class DevicePlatform {
    public static readonly DevicePlatform Desktop = new("desktop", offersAgents: true);
    public static readonly DevicePlatform Mobile = new("mobile", offersAgents: false);
    public static IReadOnlyList<DevicePlatform> All { get; } = [Desktop, Mobile];
    public string Name { get; }
    internal bool OffersAgents { get; }
    private DevicePlatform(string name, bool offersAgents) { Name = name; OffersAgents = offersAgents; }
    public static DevicePlatform? Named(string? name) => All.FirstOrDefault(platform => platform.Name == name);
}
