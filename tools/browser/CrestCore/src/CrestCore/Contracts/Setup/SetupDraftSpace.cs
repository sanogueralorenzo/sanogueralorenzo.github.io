namespace CrestCore.Contracts;

/// One Space of a manual setup: the Space `SpaceId` with the profile
/// `ProfileId`, whether the setup makes it, and the name and look it takes. A
/// name left blank stays blank here, as the person is typing it.
public sealed record SetupDraftSpace(Guid SpaceId, Guid ProfileId, bool IsNew, SpaceCustomization Customization) {
    #region Variables

    /// The name the Space shows and takes once the setup is applied: the one
    /// given, trimmed, or "Untitled Space" for a blank one.
    [Resolved]
    public string ShownName => SpaceCustomization.Resolved(Customization.Name);

    #endregion

    #region Actions - Setup

    /// The existing Space `space` as a setup starts from it, with its name and
    /// look.
    internal static SetupDraftSpace Existing(SpaceState space) => new(space.Id, space.ProfileId, IsNew: false, space.Customization);

    /// The Space with its look in `look`, keeping its name, symbol and colors.
    internal SetupDraftSpace Restyled(SetupLook look) => this with { Customization = look.Applying(Customization) };

    #endregion
}
