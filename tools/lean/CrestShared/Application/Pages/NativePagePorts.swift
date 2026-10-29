import Foundation

protocol NativePageRequest: Sendable {}
protocol NativePageReport: Sendable {}
protocol NativeDocumentReport: NativePageReport { var pageID: UUID { get } }
