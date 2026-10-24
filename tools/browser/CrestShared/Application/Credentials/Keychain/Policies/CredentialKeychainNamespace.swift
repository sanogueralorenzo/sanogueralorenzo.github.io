import Foundation

enum CredentialKeychainNamespace {
    static let productionPrefix = ProductIdentity.serviceNamespace

    static func service(
        for spaceID: UUID,
        prefix: String = productionPrefix
    ) -> String {
        "\(prefix).space.\(spaceID.uuidString.lowercased()).credential"
    }
}
