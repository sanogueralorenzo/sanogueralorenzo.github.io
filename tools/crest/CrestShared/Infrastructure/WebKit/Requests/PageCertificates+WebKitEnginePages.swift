import Foundation

extension PageCertificates {
    @MainActor func answer(on pages: WebKitEnginePages) -> Answer {
        CertificateChain(certificates: pages.page(pageID).map(pages.certificates) ?? [])
    }
}
