import Foundation

extension WebsiteDataRead {
    /// A website data reading's end changes no model: `CrestCore.readWebsiteData`
    /// hears it.
    @MainActor func apply(to state: CoreState) {}

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        batch.websiteDataRead.append(self)
    }
}
