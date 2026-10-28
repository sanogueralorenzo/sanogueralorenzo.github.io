namespace CrestCore.Contracts;

public sealed record CapacityLimits(
    int Folders,
    int FolderDepth,
    int HistoryEntries,
    int SplitMembers,
    int Spaces,
    int TabsPerSpace,
    int SyncRecords);
