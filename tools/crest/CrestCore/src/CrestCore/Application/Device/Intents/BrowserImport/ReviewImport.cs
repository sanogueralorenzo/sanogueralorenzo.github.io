using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

[MessageLimit(64 * 1024 * 1024)]
public sealed record ReviewImport(ImportSource Source, IReadOnlyList<SpaceState> Spaces, IReadOnlyList<ImportSpaceExtensions>? Extensions = null, IReadOnlyList<ImportLeftOut>? LeftOut = null, string? Title = null)
    : BrowserImportIntent {
    #region Actions - Device

    /// The flow reviews the Spaces the browser it reads brings. A read it no
    /// longer waits for changes nothing. Throws `Rejected` with `InvalidImport`
    /// for Spaces that repeat an identity or hold a split repair would
    /// rewrite, or `SpaceLimitReached` for more than a workspace holds.
    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, session) => {
        if (flow.Phase != ImportPhase.Reading || flow.Source != Source) return flow;
        if (Spaces.Select(space => space.Id).Distinct().Count() != Spaces.Count)
            throw new Rejected(new InvalidImport(ImportFlaw.UnpairedChoices));
        SessionState.RequireSpaceCapacity(0, Spaces.Count);
        foreach (var space in Spaces)
            SplitMember.RequireWellFormed([.. space.Tabs.Select(tab =>
                new SplitMember(tab.SplitGroupId, tab.Placement, tab.FolderId))]);
        return flow with {
            Step = ImportStep.Review,
            Phase = ImportPhase.Reviewing,
            Review = ImportReview.Started(Source, Spaces, Extensions ?? [], LeftOut ?? [], session) with { BrowserTitle = Title },
            Failure = null
        };
    });

    #endregion
}
