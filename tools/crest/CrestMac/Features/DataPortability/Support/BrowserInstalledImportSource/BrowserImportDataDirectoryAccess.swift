import Foundation

struct BrowserImportDataDirectoryAccess {
    let url: URL
    private let securityScopeIsActive: Bool

    init(url: URL) {
        self.url = url
        securityScopeIsActive = url.startAccessingSecurityScopedResource()
    }

    func stopAccessing() {
        if securityScopeIsActive {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
