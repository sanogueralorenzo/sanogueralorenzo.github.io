import Foundation

extension AppConfiguration {
    /// A configuration for the device this process runs on, keeping the
    /// session in `storageDirectory`, or in memory when it is nil. An import
    /// names the Spaces it brings in the person's language.
    init(storageDirectory: String?) {
        self.init(
            storageDirectory: storageDirectory, platform: .current,
            importNames: ImportSource.all.compactMap(ImportSpaceNames.init(resolving:)))
    }
}
