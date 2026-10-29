namespace CrestCore.Contracts;

public sealed class DevicePlatform {
    public static readonly DevicePlatform Desktop = new("desktop");
    public static readonly DevicePlatform Mobile = new("mobile");
    public static IReadOnlyList<DevicePlatform> All { get; } = [Desktop, Mobile];
    public string Name { get; }
    private DevicePlatform(string name) { Name = name; }
    public static DevicePlatform? Named(string? name) => All.FirstOrDefault(platform => platform.Name == name);
}
