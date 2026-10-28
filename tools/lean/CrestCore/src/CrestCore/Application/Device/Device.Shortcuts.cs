using CrestCore.Contracts;

namespace CrestCore.Application;

/// The fixed shortcut bindings offered by this device's engines.
internal sealed partial class Device {
    #region Actions - Bindings

    public ShortcutsChanged? ShortcutsAfter(IReadOnlyList<ShortcutCommand> before, IReadOnlyList<ShortcutCommand> offered) {
        var previous = Shortcuts(before);
        var next = Shortcuts(offered);
        return next.Bindings.SequenceEqual(previous.Bindings) ? null : next;
    }

    internal ShortcutsChanged Shortcuts(IReadOnlyList<ShortcutCommand> offered) =>
        new([.. offered.Select(command => new ShortcutBinding(command, command.DefaultShortcut(platform)?.Keys))]);

    #endregion
}
