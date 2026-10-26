using CrestCore.Application;

namespace CrestCore.Contracts;

/// Gives a split of two or more tabs an emoji icon: the first character of
/// `Emoji`, given as the emoji or spelled as a symbol. Null clears it. Refused
/// with `InvalidSplitIcon` when that character does not present as an emoji.
public sealed record SetSplitIcon(Guid WorkspaceId, Guid SpaceId, Guid GroupId, string? Emoji) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// An emoji icon is kept as the one character that presents as an emoji.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        string? symbol = Emoji is null ? null
            : (EmojiIcon.Chosen(Emoji) ?? throw new Rejected(new InvalidSplitIcon(GroupId))).Symbol;
        return workspace.Identifying(turn.Basis, SpaceId, GroupId, turn.Now, group => group with { CustomIconSymbol = symbol },
            (group, changedAt) => group with { IconModifiedAt = changedAt });
    }

    #endregion
}
