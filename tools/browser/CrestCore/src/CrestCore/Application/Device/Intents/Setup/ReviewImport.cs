using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// The Spaces `Source` brings, as `ReadImport` answered them, with where each
/// of its saved passwords belongs, from which setup counts the passwords that
/// belong with each Space, the extensions each Space offers to install, and
/// what the read left out, which the review shows. Setup reviews them: each
/// Space joins the existing Space of the same name, leaving out the tabs that
/// Space holds, or else comes in as a new Space while the workspace has room
/// for it, and the person looks at the first.
///
/// Refused with `InvalidImport` for Spaces that repeat an identity or hold a
/// split repair would rewrite.
[MessageLimit(64 * 1024 * 1024)]
public sealed record ReviewImport(ImportSource Source, IReadOnlyList<SpaceState> Spaces, IReadOnlyList<ImportPasswordSource> Passwords,
    IReadOnlyList<ImportSpaceExtensions>? Extensions = null, IReadOnlyList<ImportLeftOut>? LeftOut = null, string? Title = null)
    : SetupFlowIntent {
    #region Actions - Device

    /// The flow reviews the Spaces the browser it reads brings. A read it no
    /// longer waits for changes nothing. Throws `Rejected` with `InvalidImport`
    /// for Spaces that repeat an identity or hold a split repair would
    /// rewrite, or `SpaceLimitReached` for more than a workspace holds.
    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseFlow(turn.Changes, (flow, session) => {
        if (flow.Phase != SetupPhase.Reading || flow.Source != Source) return flow;
        if (Spaces.Select(space => space.Id).Distinct().Count() != Spaces.Count)
            throw new Rejected(new InvalidImport(ImportFlaw.UnpairedChoices));
        SessionState.RequireSpaceCapacity(0, Spaces.Count);
        foreach (var space in Spaces)
            SplitMember.RequireWellFormed([.. space.Tabs.Select(tab =>
                new SplitMember(tab.SplitGroupId, tab.Placement, tab.FolderId))]);
        return flow with {
            Step = SetupStep.Review,
            Phase = SetupPhase.Reviewing,
            Review = SetupImportReview.Started(Source, Spaces, Source.PasswordCounts(Passwords, Spaces),
                Extensions ?? [], LeftOut ?? [], session, flow.Look) with { BrowserTitle = Title },
            Failure = null
        };
    });

    #endregion
}
