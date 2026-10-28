using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    #region Actions - Live folders

    [Fact]
    public void LiveFolderRefreshKeepsTabIdentityAndRenamesAndArchivesExpiredEntries() {
        var fixture = SavedSession();
        using var device = new TestDevice(fixture.Document["session"]!);
        var core = device.Authority;
        var folder = Guid.NewGuid();
        var profile = core.Current.Spaces[0].ProfileId;
        RefreshLiveFolder Refresh(params LiveFolderTab[] items) =>
            new(device.Workspace, fixture.Space, profile, folder, LiveFolderSource.GitHubPullRequests, items);
        var first = new LiveFolderTab("https://github.com/team/browser/pull/41", "First review");
        var second = new LiveFolderTab("https://github.com/team/browser/pull/42", "Second review");
        device.Send(Refresh(first, second));
        var original = core.Current.Spaces[0].Tabs.Single(tab => tab.SavedUrl == first.Url);
        Assert.Equal(folder, original.FolderId);
        Assert.Equal(TabPlacement.Saved, original.Placement);
        device.Send(new RenameTab(device.Workspace, fixture.Space, original.Id, "Mine"));
        device.Send(Refresh(first with { Title = "Updated first review" }));
        var kept = core.Current.Spaces[0].Tabs.Single(tab => tab.SavedUrl == first.Url);
        Assert.Equal(original.Id, kept.Id);
        Assert.Equal("Mine", kept.CustomTitle);
        Assert.Equal("Updated first review", kept.Title);
        Assert.Single(core.Current.Spaces[0].Tabs, tab => tab.FolderId == folder);
        Assert.Contains(core.Current.Spaces[0].ArchivedTabs, item => item.Tab.Url == second.Url && item.Reason == ArchiveReason.Closed);
        Assert.Contains(core.Current.Spaces[0].Tabs, tab => tab.Id == fixture.Tab);

        var stored = JsonNode.Parse(core.Checkpoint().Read("core"))!;
        using var relaunched = new TestDevice(stored);
        Assert.Equal(LiveFolderSource.GitHubPullRequests, relaunched.Authority.Current.Spaces[0].Folders.Single(f => f.Id == folder).Source);
        Assert.Equal(kept, relaunched.Authority.Current.Spaces[0].Tabs.Single(tab => tab.Id == kept.Id));
        var projected = NativeSyncProjection.Project(stored.AsObject(), SyncProjectionPreferences(), []);
        var payload = projected.Single(record => record!["type"]!.GetValue<string>() == "folder"
            && Guid.Parse(record["value"]!["id"]!["rawValue"]!.GetValue<string>()) == folder)!["value"]!;
        Assert.Equal("githubPullRequests", payload["liveFolderSource"]!.GetValue<string>());
        var body = SyncRecordBody.Read(CodecBody("folder", payload.AsObject()), isTombstone: false, SyncPayloadForm.Journal);
        Assert.Equal("githubPullRequests", body.Write(SyncPayloadForm.Cloud)["value"]!["liveFolderSource"]!.GetValue<string>());
        var window = device.Open(fixture.Space);
        device.Send(new DeleteTab(device.Workspace, window, fixture.Space, kept.Id));
        device.Send(Refresh(first));
        Assert.DoesNotContain(core.Current.Spaces[0].Tabs, tab => tab.SavedUrl == first.Url);

    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void DeletingALiveFolderPersistsDismissalAndRejectsLateRefreshUntilExplicitlyEnabled(bool nested) {
        var fixture = SavedSession();
        using var device = new TestDevice(fixture.Document["session"]!);
        var core = device.Authority;
        var folder = Guid.NewGuid();
        var profile = core.Current.Spaces[0].ProfileId;
        var refresh = new RefreshLiveFolder(device.Workspace, fixture.Space, profile, folder,
            LiveFolderSource.GitHubPullRequests, [new("https://github.com/team/browser/pull/41", "Review")]);
        device.Send(refresh);
        var tab = core.Current.Spaces[0].Tabs.Single(item => item.FolderId == folder);
        var deletedFolder = folder;
        if (nested) {
            deletedFolder = Guid.NewGuid();
            device.Send(new CreateFolder(device.Workspace, fixture.Space, deletedFolder, TabPlacement.Saved, null,
                "Parent", null, [], false));
            device.Send(new MoveFolder(device.Workspace, fixture.Space, folder, null, deletedFolder, null, null));
        }
        device.Send(new DeleteFolder(device.Workspace, fixture.Space, deletedFolder));
        Assert.True(core.Current.Spaces[0].Settings.IsGitHubFolderDismissed);
        Assert.DoesNotContain(core.Current.Spaces[0].Folders, item => item.Source == LiveFolderSource.GitHubPullRequests);
        Assert.DoesNotContain(core.Current.Spaces[0].Tabs, item => item.Id == tab.Id);
        Assert.Contains(core.Current.Spaces[0].ArchivedTabs, item => item.Tab.Id == tab.Id && item.Reason == ArchiveReason.Deleted);
        var dismissed = core.Current;
        Assert.IsType<InvalidLiveFolder>(Assert.Throws<Rejected>(() => device.Send(refresh)).Rejection);
        Assert.Same(dismissed, core.Current);
        var stored = JsonNode.Parse(core.Checkpoint().Read("core"))!.AsObject();
        using var relaunched = new TestDevice(stored);
        Assert.True(relaunched.Authority.Current.Spaces[0].Settings.IsGitHubFolderDismissed);
        var materialized = NativeSyncMaterializer.Materialize(stored, SyncProjectionPreferences(), SpaceRecords(stored), 42);
        Assert.True(StoredSessionCodec.DecodeSession(materialized).Spaces.Single(space => space.Id == fixture.Space)
            .Settings.IsGitHubFolderDismissed);
        var replacement = Guid.NewGuid();
        device.Send(new EnableGitHubLiveFolder(device.Workspace, fixture.Space, profile, replacement));
        Assert.False(core.Current.Spaces[0].Settings.IsGitHubFolderDismissed);
        device.Send(refresh with { FolderId = replacement });
        var refreshed = core.Current.Spaces[0];
        var managed = refreshed.Tabs.Single(item => item.FolderId == replacement);
        device.Send(new EnableGitHubLiveFolder(device.Workspace, fixture.Space, profile, Guid.NewGuid()));
        Assert.Single(core.Current.Spaces[0].Folders, item => item.Source == LiveFolderSource.GitHubPullRequests);
        Assert.Equal(managed, core.Current.Spaces[0].Tabs.Single(item => item.Id == managed.Id));
        var enabled = JsonNode.Parse(core.Checkpoint().Read("core"))!.AsObject();
        Assert.False(StoredSessionCodec.DecodeSession(NativeSyncMaterializer.Materialize(enabled,
            SyncProjectionPreferences(), SpaceRecords(enabled), 42)).Spaces.Single(space => space.Id == fixture.Space)
            .Settings.IsGitHubFolderDismissed);
    }

    [Fact]
    public void LiveFolderOptionsPersistSyncAndRejectRefreshesFromPreviousFilters() {
        var fixture = SavedSession();
        using var device = new TestDevice(fixture.Document["session"]!);
        var core = device.Authority;
        var folder = Guid.NewGuid();
        var profile = core.Current.Spaces[0].ProfileId;
        var item = new LiveFolderTab("https://github.com/team/browser/pull/41", "Review");
        device.Send(new RefreshLiveFolder(device.Workspace, fixture.Space, profile, folder,
            LiveFolderSource.GitHubPullRequests, [item]));
        var defaults = core.Current.Spaces[0].Folders.Single(f => f.Id == folder).GitHubOptions;
        Assert.True(defaults.AuthorMe);
        Assert.True(defaults.AssignedMe);
        Assert.False(defaults.ReviewRequested);
        Assert.True(defaults.IncludeDrafts);
        var options = new GitHubLiveFolderOptions(true, false, true, false,
            [" z/browser ", "A/browser", "a/browser"], LiveFolderRefreshInterval.FourHours);
        device.Send(new SetGitHubLiveFolderOptions(device.Workspace, fixture.Space, profile, folder, options));
        var configured = core.Current.Spaces[0].Folders.Single(f => f.Id == folder).GitHubOptions;
        Assert.Equal(["A/browser", "z/browser"], configured.ExcludedRepositories);
        var before = core.Current;
        Assert.IsType<InvalidLiveFolder>(Assert.Throws<Rejected>(() => device.Send(new RefreshLiveFolder(
            device.Workspace, fixture.Space, profile, folder, LiveFolderSource.GitHubPullRequests, [], defaults))).Rejection);
        Assert.Same(before, core.Current);
        var stored = JsonNode.Parse(core.Checkpoint().Read("core"))!;
        using var relaunched = new TestDevice(stored);
        Assert.True(configured.Matches(relaunched.Authority.Current.Spaces[0].Folders.Single(f => f.Id == folder).GitHubOptions));
        var projected = NativeSyncProjection.Project(stored.AsObject(), SyncProjectionPreferences(), []);
        var payload = projected.Single(record => record!["type"]!.GetValue<string>() == "folder"
            && Guid.Parse(record["value"]!["id"]!["rawValue"]!.GetValue<string>()) == folder)!["value"]!;
        var body = SyncRecordBody.Read(CodecBody("folder", payload.AsObject()), false, SyncPayloadForm.Journal);
        Assert.Equal("4hours", body.Write(SyncPayloadForm.Cloud)["value"]!["githubOptions"]!["interval"]!.GetValue<string>());
        var materialized = NativeSyncMaterializer.Materialize(stored.AsObject(), SyncProjectionPreferences(),
            SpaceRecords(stored), 42);
        var restored = StoredSessionCodec.DecodeSession(materialized);
        Assert.True(configured.Matches(restored.Spaces.Single(space => space.Id == fixture.Space)
            .Folders.Single(f => f.Id == folder).GitHubOptions));
        var none = configured with { AuthorMe = false, AssignedMe = false, ReviewRequested = false };
        device.Send(new SetGitHubLiveFolderOptions(device.Workspace, fixture.Space, profile, folder, none));
        Assert.Contains(core.Current.Spaces[0].Tabs, tab => tab.FolderId == folder && tab.SavedUrl == item.Url);
    }

    [Fact]
    public void LiveFolderOptionsCannotCrossProfilesOrModifyPersonalFoldersOrIntroduceQuerySyntax() {
        var fixture = SavedSession();
        using var device = new TestDevice(fixture.Document["session"]!);
        var before = device.Authority.Current;
        var space = before.Spaces[0];
        Assert.IsType<InvalidLiveFolder>(Assert.Throws<Rejected>(() => device.Send(new SetGitHubLiveFolderOptions(
            device.Workspace, fixture.Space, Guid.NewGuid(), space.Folders[0].Id, GitHubLiveFolderOptions.Default))).Rejection);
        Assert.IsType<InvalidLiveFolder>(Assert.Throws<Rejected>(() => device.Send(new SetGitHubLiveFolderOptions(
            device.Workspace, fixture.Space, space.ProfileId, space.Folders[0].Id, GitHubLiveFolderOptions.Default))).Rejection);
        var folder = Guid.NewGuid();
        device.Send(new RefreshLiveFolder(device.Workspace, fixture.Space, space.ProfileId, folder,
            LiveFolderSource.GitHubPullRequests, []));
        var valid = device.Authority.Current;
        foreach (var repository in new[] { "team/repo OR author:someone", "https://example.com/team/repo", "../repo/extra" }) {
            Assert.IsType<InvalidLiveFolder>(Assert.Throws<Rejected>(() => device.Send(new SetGitHubLiveFolderOptions(
                device.Workspace, fixture.Space, space.ProfileId, folder,
                GitHubLiveFolderOptions.Default with { ExcludedRepositories = [repository] }))).Rejection);
            Assert.Same(valid, device.Authority.Current);
        }
        var privateWorkspace = device.Attach(fixture.Document["session"]!.DeepClone(), WorkspaceKind.Private);
        Assert.IsType<PersistentWorkspaceRequired>(Assert.Throws<Rejected>(() => device.Send(new SetGitHubLiveFolderOptions(
            privateWorkspace, fixture.Space, space.ProfileId, folder, GitHubLiveFolderOptions.Default))).Rejection);
    }

    [Fact]
    public void ExpiredLiveFolderItemsKeepPersonalNavigationOutsideTheManagedFolder() {
        var fixture = SavedSession();
        var session = fixture.Document["session"]!;
        var space = session["spaces"]![0]!;
        space["folders"]![0]!["liveFolderSource"] = "githubPullRequests";
        var tab = space["tabs"]![0]!;
        tab["savedURL"] = "https://github.com/team/browser/pull/41";
        tab["url"] = "https://github.com/team/browser/pull/41/files";
        using var device = new TestDevice(session);
        var before = device.Authority.Current.Spaces[0];
        device.Send(new RefreshLiveFolder(device.Workspace, fixture.Space, before.ProfileId, before.Folders[0].Id,
            LiveFolderSource.GitHubPullRequests, []));
        var personal = device.Authority.Current.Spaces[0].Tabs.Single(item => item.Id == fixture.Tab);
        Assert.Equal(TabPlacement.Current, personal.Placement);
        Assert.Null(personal.FolderId);
        Assert.Equal("https://github.com/team/browser/pull/41/files", personal.Url);
        Assert.Equal(before.Tabs[0].CustomTitle, personal.CustomTitle);
        Assert.DoesNotContain(device.Authority.Current.Spaces[0].ArchivedTabs, item => item.Tab.Id == personal.Id);
    }

    [Theory]
    [InlineData("https://github.com.example/team/browser/pull/1")]
    [InlineData("https://github.com@attacker.example/team/browser/pull/1")]
    [InlineData("http://github.com/team/browser/pull/1")]
    [InlineData("https://github.com/team/browser/pull/1?redirect=bad")]
    [InlineData("https://github.com/team/browser/issues/1")]
    public void LiveFolderRefreshRejectsUntrustedAddressesAtomically(string url) {
        var fixture = SavedSession();
        using var device = new TestDevice(fixture.Document["session"]!);
        var before = device.Authority.Current;
        Assert.IsType<InvalidLiveFolder>(Assert.Throws<Rejected>(() => device.Send(new RefreshLiveFolder(
            device.Workspace, fixture.Space, before.Spaces[0].ProfileId, Guid.NewGuid(), LiveFolderSource.GitHubPullRequests,
            [new(url, "Untrusted")]))).Rejection);
        Assert.Same(before, device.Authority.Current);
    }

    [Fact]
    public void LiveFolderRefreshCannotCrossProfilesOrOverwritePersonalFoldersOrEnterPrivateWorkspaces() {
        var fixture = SavedSession();
        var session = fixture.Document["session"]!;
        using var device = new TestDevice(session);
        var before = device.Authority.Current;
        var space = before.Spaces[0];
        RefreshLiveFolder Refresh(Guid workspace, Guid profile, Guid folder) =>
            new(workspace, fixture.Space, profile, folder, LiveFolderSource.GitHubPullRequests, []);
        Assert.IsType<InvalidLiveFolder>(Assert.Throws<Rejected>(() =>
            device.Send(Refresh(device.Workspace, Guid.NewGuid(), Guid.NewGuid()))).Rejection);
        Assert.IsType<FolderAlreadyExists>(Assert.Throws<Rejected>(() =>
            device.Send(Refresh(device.Workspace, space.ProfileId, space.Folders[0].Id))).Rejection);
        Assert.IsType<InvalidLiveFolder>(Assert.Throws<Rejected>(() => device.Send(new EnableGitHubLiveFolder(
            device.Workspace, fixture.Space, Guid.NewGuid(), Guid.NewGuid()))).Rejection);
        Assert.IsType<FolderAlreadyExists>(Assert.Throws<Rejected>(() => device.Send(new EnableGitHubLiveFolder(
            device.Workspace, fixture.Space, space.ProfileId, space.Folders[0].Id))).Rejection);
        Assert.Same(before, device.Authority.Current);
        var privateWorkspace = device.Attach(session.DeepClone(), WorkspaceKind.Private);
        Assert.IsType<PersistentWorkspaceRequired>(Assert.Throws<Rejected>(() =>
            device.Send(Refresh(privateWorkspace, space.ProfileId, Guid.NewGuid()))).Rejection);
        Assert.IsType<PersistentWorkspaceRequired>(Assert.Throws<Rejected>(() => device.Send(new EnableGitHubLiveFolder(
            privateWorkspace, fixture.Space, space.ProfileId, Guid.NewGuid()))).Rejection);
    }

    #endregion
}
