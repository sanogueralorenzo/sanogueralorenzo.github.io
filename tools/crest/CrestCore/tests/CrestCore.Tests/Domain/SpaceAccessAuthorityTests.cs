using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// A grant covers the exact Space profile its request named, and locking a
/// Space revokes every profile of it without touching another's request.
public sealed class SpaceAccessAuthorityTests {
    private static SpaceAccessAssignment Assignment() => new(Guid.NewGuid(), Guid.NewGuid());

    private static void Grant(SpaceAccessAuthority access, SpaceAccessAssignment assignment) {
        var request = Guid.NewGuid();
        access.Begin(assignment, requiresAuthentication: true, request);
        access.Finish(assignment.Space, request, authenticated: true);
    }

    [Fact]
    public void AGrantCoversOnlyTheProfileItsRequestNamed() {
        var access = new SpaceAccessAuthority();
        var target = Assignment();
        var replacement = target with { Profile = Guid.NewGuid() };
        Grant(access, target);

        Assert.False(access.IsLocked(target, requiresAuthentication: true));
        Assert.True(access.IsLocked(replacement, requiresAuthentication: true));
        Assert.True(new SpaceAccessAuthority().IsLocked(target, requiresAuthentication: true));
    }

    [Fact]
    public void LockingOneSpaceRevokesAllItsProfilesWithoutCancellingAnotherRequest() {
        var access = new SpaceAccessAuthority();
        var first = Assignment();
        var replacement = first with { Profile = Guid.NewGuid() };
        var other = Assignment();
        Grant(access, first);
        Grant(access, replacement);
        var request = Guid.NewGuid();
        access.Begin(other, requiresAuthentication: true, request);

        Assert.Equal(new HashSet<SpaceAccessAssignment> { first, replacement }, access.Lock(first.Space).ToHashSet());
        Assert.True(access.IsLocked(first, requiresAuthentication: true));
        Assert.True(access.IsLocked(replacement, requiresAuthentication: true));
        Assert.Equal([other], access.Finish(other.Space, request, authenticated: true));
        Assert.False(access.IsLocked(other, requiresAuthentication: true));
    }
}
